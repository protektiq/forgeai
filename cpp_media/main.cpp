/*
 * cpp_media – HTTP service for image processing (resize, thumbnail, format conversion).
 * Uses libvips for image ops and cpp-httplib for HTTP.
 */

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <memory>
#include <functional>

#include "httplib.h"
#include <vips/vips8>

namespace {

const int DEFAULT_PORT = 8080;
const int DEFAULT_THUMBNAIL_SIZE = 256;
const int DEFAULT_RESIZE_MAX = 1200;
const char* DEFAULT_OUTPUT_FORMAT = "jpg";

/* Simple base64 encode (for JSON response). */
std::string base64_encode(const unsigned char* data, size_t len) {
  static const char tbl[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve(((len + 2) / 3) * 4);
  for (size_t i = 0; i < len; i += 3) {
    unsigned int n = static_cast<unsigned int>(data[i]) << 16;
    if (i + 1 < len) n |= static_cast<unsigned int>(data[i + 1]) << 8;
    if (i + 2 < len) n |= static_cast<unsigned int>(data[i + 2]);
    out += tbl[(n >> 18) & 63];
    out += tbl[(n >> 12) & 63];
    out += (i + 1 < len) ? tbl[(n >> 6) & 63] : '=';
    out += (i + 2 < len) ? tbl[n & 63] : '=';
  }
  return out;
}

/* Simple base64 decode (for JSON request image_base64). */
std::vector<unsigned char> base64_decode(const std::string& in) {
  std::vector<unsigned char> out;
  if (in.empty()) return out;
  out.reserve((in.size() * 3) / 4);
  int buf = 0, bits = 0;
  for (unsigned char c : in) {
    if (c == '=') break;
    int v = -1;
    if (c >= 'A' && c <= 'Z') v = c - 'A';
    else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
    else if (c >= '0' && c <= '9') v = c - '0' + 52;
    else if (c == '+') v = 62;
    else if (c == '/') v = 63;
    if (v < 0) continue;
    buf = (buf << 6) | v;
    bits += 6;
    if (bits >= 8) {
      out.push_back(static_cast<unsigned char>((buf >> (bits - 8)) & 0xff));
      bits -= 8;
    }
  }
  return out;
}

std::string suffix_for_format(const std::string& fmt) {
  std::string s = fmt;
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  if (s == "jpg" || s == "jpeg") return ".jpg";
  if (s == "png") return ".png";
  return ".jpg";
}

std::string content_type_for_suffix(const std::string& suffix) {
  if (suffix == ".jpg") return "image/jpeg";
  if (suffix == ".png") return "image/png";
  return "image/jpeg";
}

/* Standard error response shape (see docs/contracts/error-response.md). */
void json_escape(std::ostringstream& out, const std::string& s) {
  for (unsigned char c : s) {
    if (c == '"') out << "\\\"";
    else if (c == '\\') out << "\\\\";
    else if (c == '\n') out << "\\n";
    else if (c == '\r') out << "\\r";
    else if (c == '\t') out << "\\t";
    else if (c >= 32 && c < 127) out << static_cast<char>(c);
    else out << " ";
  }
}

void set_error_response(httplib::Response& res,
                        int status,
                        const std::string& code,
                        const std::string& message,
                        const std::string& correlation_id) {
  res.status = status;
  std::ostringstream json;
  json << "{\"error\":{\"code\":\"";
  json_escape(json, code);
  json << "\",\"message\":\"";
  json_escape(json, message);
  json << "\",\"correlation_id\":\"";
  json_escape(json, correlation_id);
  json << "\"}}";
  res.set_content(json.str(), "application/json");
}

struct ProcessParams {
  int thumbnail_size = DEFAULT_THUMBNAIL_SIZE;
  int resize_max = DEFAULT_RESIZE_MAX;
  std::string output_format = DEFAULT_OUTPUT_FORMAT;
  bool want_thumbnail = true;
  bool want_resize = true;
};

/* Process image bytes: produce thumbnail and optionally resized image. */
bool process_image(const unsigned char* data,
                  size_t size,
                  const ProcessParams& params,
                  std::string& thumbnail_base64,
                  std::string& thumbnail_content_type,
                  std::string& processed_base64,
                  std::string& processed_content_type,
                  std::string& error_msg) {
  using namespace vips;
  const std::string suffix = suffix_for_format(params.output_format);
  const std::string ct = content_type_for_suffix(suffix);

  try {
    VImage img = VImage::new_from_buffer(
        reinterpret_cast<const void*>(data), size, "");

    /* Thumbnail */
    if (params.want_thumbnail && size > 0) {
      VImage thumb = VImage::thumbnail_buffer(
          const_cast<void*>(reinterpret_cast<const void*>(data)),
          size,
          params.thumbnail_size,
          VImage::option()->set("height", params.thumbnail_size));
      void* thumb_buf = nullptr;
      size_t thumb_len = 0;
      thumb.write_to_buffer(suffix.c_str(), &thumb_buf, &thumb_len);
      if (thumb_buf && thumb_len > 0) {
        thumbnail_base64 = base64_encode(static_cast<unsigned char*>(thumb_buf),
                                        thumb_len);
        thumbnail_content_type = ct;
        g_free(thumb_buf);
      }
    }

    /* Processed (resize + convert format) */
    if (params.want_resize && size > 0) {
      VImage out = img;
      int w = img.width();
      int h = img.height();
      if (w > params.resize_max || h > params.resize_max) {
        double scale = std::min(
            static_cast<double>(params.resize_max) / static_cast<double>(w),
            static_cast<double>(params.resize_max) / static_cast<double>(h));
        out = img.resize(scale);
      }
      void* proc_buf = nullptr;
      size_t proc_len = 0;
      out.write_to_buffer(suffix.c_str(), &proc_buf, &proc_len);
      if (proc_buf && proc_len > 0) {
        processed_base64 = base64_encode(static_cast<unsigned char*>(proc_buf),
                                         proc_len);
        processed_content_type = ct;
        g_free(proc_buf);
      }
    }

    return true;
  } catch (const VError& e) {
    error_msg = e.what();
    return false;
  }
}

/* Parse optional int from string. */
int parse_int(const std::string& s, int default_val) {
  if (s.empty()) return default_val;
  try {
    return std::stoi(s);
  } catch (...) {
    return default_val;
  }
}

/* Check if operations string contains "thumbnail" or "resize". */
void parse_operations(const std::string& ops,
                     bool& want_thumbnail,
                     bool& want_resize) {
  want_thumbnail = false;
  want_resize = false;
  std::string lower = ops;
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  if (lower.find("thumbnail") != std::string::npos) want_thumbnail = true;
  if (lower.find("resize") != std::string::npos) want_resize = true;
  if (!want_thumbnail && !want_resize) {
    want_thumbnail = true;
    want_resize = true;
  }
}

}  // namespace

int main(int argc, char* argv[]) {
  if (vips_init(argv[0])) {
    vips_error_exit(nullptr);
  }
  int port = DEFAULT_PORT;
  if (argc >= 2) {
    try {
      port = std::stoi(argv[1]);
    } catch (...) {}
  }
  if (port <= 0 || port > 65535) port = DEFAULT_PORT;

  httplib::Server svr;

  /* GET /health */
  svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
    res.set_header("Content-Type", "application/json");
    res.set_content("{\"status\":\"ok\",\"service\":\"cpp_media\"}", "application/json");
  });

  /* POST /process: multipart (file=...) or JSON (image_base64=...). */
  svr.Post("/process", [](const httplib::Request& req, httplib::Response& res) {
    res.set_header("Content-Type", "application/json");

    std::string corr = req.get_header_value("X-Correlation-Id");
    if (corr.empty()) corr = req.get_header_value("X-Request-Id");
    if (!corr.empty()) {
      std::cerr << "[cpp_media] correlation_id=" << corr << " processing /process" << std::endl;
    }

    ProcessParams params;
    const unsigned char* image_data = nullptr;
    size_t image_size = 0;
    std::vector<unsigned char> decoded;

    /* Multipart form */
    if (req.form.has_file("file")) {
      const auto& file = req.form.get_file("file");
      image_data = reinterpret_cast<const unsigned char*>(file.content.data());
      image_size = file.content.size();
      if (req.form.has_field("thumbnail_size")) {
        params.thumbnail_size = parse_int(req.form.get_field("thumbnail_size"),
                                          DEFAULT_THUMBNAIL_SIZE);
      }
      if (req.form.has_field("resize_max")) {
        params.resize_max = parse_int(req.form.get_field("resize_max"),
                                     DEFAULT_RESIZE_MAX);
      }
      if (req.form.has_field("output_format")) {
        params.output_format = req.form.get_field("output_format");
      }
      if (req.form.has_field("operations")) {
        parse_operations(req.form.get_field("operations"),
                        params.want_thumbnail,
                        params.want_resize);
      }
    } else {
      /* JSON body */
      if (req.get_header_value("Content-Type").find("application/json") ==
          std::string::npos) {
        set_error_response(res, 400, "invalid_request",
            "Missing file or JSON body; use multipart file= or "
            "application/json with image_base64",
            corr);
        return;
      }
      /* Minimal JSON parse for image_base64 and options */
      const std::string& body = req.body;
      size_t pos = body.find("\"image_base64\"");
      if (pos == std::string::npos) {
        set_error_response(res, 400, "invalid_request",
            "Missing image_base64 in JSON", corr);
        return;
      }
      pos = body.find(':', pos);
      if (pos == std::string::npos) {
        set_error_response(res, 400, "invalid_request", "Invalid JSON", corr);
        return;
      }
      pos = body.find('"', pos + 1);
      if (pos == std::string::npos) {
        set_error_response(res, 400, "invalid_request", "Invalid JSON", corr);
        return;
      }
      size_t start = pos + 1;
      size_t end = body.find('"', start);
      if (end == std::string::npos) end = body.size();
      std::string b64 = body.substr(start, end - start);
      decoded = base64_decode(b64);
      if (decoded.empty()) {
        set_error_response(res, 400, "invalid_request",
            "Invalid or empty image_base64", corr);
        return;
      }
      image_data = decoded.data();
      image_size = decoded.size();

      /* Optional JSON fields (simple string search) */
      auto get_json_int = [&body](const char* key, int def) {
        std::string needle = std::string("\"") + key + "\":";
        size_t p = body.find(needle);
        if (p == std::string::npos) return def;
        p += needle.size();
        while (p < body.size() && (body[p] == ' ' || body[p] == '\t')) p++;
        if (p >= body.size()) return def;
        size_t q = p;
        while (q < body.size() && body[q] >= '0' && body[q] <= '9') q++;
        if (q == p) return def;
        try {
          return std::stoi(body.substr(p, q - p));
        } catch (...) {
          return def;
        }
      };
      auto get_json_str = [&body](const char* key, const char* def) {
        std::string needle = std::string("\"") + key + "\":\"";
        size_t p = body.find(needle);
        if (p == std::string::npos) return std::string(def);
        p += needle.size();
        size_t q = body.find('"', p);
        if (q == std::string::npos) return std::string(def);
        return body.substr(p, q - p);
      };
      params.thumbnail_size = get_json_int("thumbnail_size", DEFAULT_THUMBNAIL_SIZE);
      params.resize_max = get_json_int("resize_max", DEFAULT_RESIZE_MAX);
      params.output_format = get_json_str("output_format", DEFAULT_OUTPUT_FORMAT);
      std::string ops = get_json_str("operations", "thumbnail,resize");
      parse_operations(ops, params.want_thumbnail, params.want_resize);
    }

    if (!image_data || image_size == 0) {
      set_error_response(res, 400, "invalid_request", "No image data", corr);
      return;
    }

    std::string thumb_b64, thumb_ct, proc_b64, proc_ct, err;
    bool ok = process_image(image_data,
                           image_size,
                           params,
                           thumb_b64,
                           thumb_ct,
                           proc_b64,
                           proc_ct,
                           err);
    if (!ok) {
      set_error_response(res, 422, "validation_error", err, corr);
      return;
    }

    std::ostringstream out;
    out << "{\"thumbnail_base64\":\"";
    for (char c : thumb_b64) {
      if (c == '"') out << "\\\"";
      else if (c == '\\') out << "\\\\";
      else out << c;
    }
    out << "\",\"thumbnail_content_type\":\"" << thumb_ct << "\"";
    if (!proc_b64.empty()) {
      out << ",\"processed_base64\":\"";
      for (char c : proc_b64) {
        if (c == '"') out << "\\\"";
        else if (c == '\\') out << "\\\\";
        else out << c;
      }
      out << "\",\"processed_content_type\":\"" << proc_ct << "\"";
    }
    out << "}";
    res.set_content(out.str(), "application/json");
  });

  /* Standard error shape for uncaught exceptions (500). */
  svr.set_exception_handler([](const httplib::Request& req, httplib::Response& res, std::exception_ptr) {
    res.set_header("Content-Type", "application/json");
    std::string corr = req.get_header_value("X-Correlation-Id");
    if (corr.empty()) corr = req.get_header_value("X-Request-Id");
    set_error_response(res, 500, "internal_error", "An unexpected error occurred", corr);
  });

  std::cout << "cpp_media listening on port " << port << std::endl;
  if (!svr.listen("0.0.0.0", port)) {
    std::cerr << "Failed to listen on port " << port << std::endl;
    vips_shutdown();
    return 1;
  }

  vips_shutdown();
  return 0;
}
