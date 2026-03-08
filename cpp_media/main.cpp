/*
 * cpp_media – HTTP service for image processing (resize, thumbnail, format conversion).
 * Uses libvips for image ops and cpp-httplib for HTTP.
 */

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <memory>
#include <functional>

#include "httplib.h"
#include "profiles.hpp"
#include "request_parser.hpp"
#include <vips/vips8>

namespace {

const int DEFAULT_PORT = 8080;
const int DEFAULT_THUMBNAIL_SIZE = 256;
const int DEFAULT_RESIZE_MAX = 1200;

/* Structured log: one JSON object per line to stderr with timestamp, service, level, correlation_id, message, optional error_code. */
void log_json(const std::string& level,
              const std::string& correlation_id,
              const std::string& message,
              const std::string& error_code = "") {
  auto now = std::chrono::system_clock::now();
  auto t = std::chrono::system_clock::to_time_t(now);
  std::ostringstream ts;
  ts << std::put_time(std::gmtime(&t), "%Y-%m-%dT%H:%M:%S");
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
  ts << '.' << std::setfill('0') << std::setw(3) << ms.count() << 'Z';

  std::ostringstream out;
  out << "{\"timestamp\":\"" << ts.str() << "\",\"service\":\"cpp_media\",\"level\":\"" << level << "\"";
  if (!correlation_id.empty()) out << ",\"correlation_id\":\"";
  for (char c : correlation_id) {
    if (c == '"' || c == '\\') out << '\\';
    out << c;
  }
  if (!correlation_id.empty()) out << "\"";
  out << ",\"message\":\"";
  for (unsigned char c : message) {
    if (c == '"') out << "\\\"";
    else if (c == '\\') out << "\\\\";
    else if (c == '\n') out << "\\n";
    else if (c == '\r') out << "\\r";
    else if (c == '\t') out << "\\t";
    else if (c >= 32 && c < 127) out << static_cast<char>(c);
    else out << " ";
  }
  out << "\"";
  if (!error_code.empty()) {
    out << ",\"error_code\":\"";
    for (char c : error_code) {
      if (c == '"' || c == '\\') out << '\\';
      out << c;
    }
    out << "\"";
  }
  out << "}\n";
  std::cerr << out.str();
}

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

/* Process image bytes: produce thumbnail and optionally resized image. */
bool process_image(const unsigned char* data,
                  size_t size,
                  const cpp_media::ProcessParams& params,
                  std::string& thumbnail_base64,
                  std::string& thumbnail_content_type,
                  std::string& processed_base64,
                  std::string& processed_content_type,
                  std::string& error_msg) {
  using namespace vips;
  const std::string suffix = suffix_for_format(params.output_format);
  const std::string ct = content_type_for_suffix(suffix);
  std::string write_suffix = suffix;
  if (params.jpeg_quality > 0 && (suffix == ".jpg" || suffix == ".jpeg")) {
    write_suffix = ".jpg[Q=" + std::to_string(params.jpeg_quality) + "]";
  }

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
      thumb.write_to_buffer(write_suffix.c_str(), &thumb_buf, &thumb_len);
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
      int max_w = params.resize_width > 0 ? params.resize_width : params.resize_max;
      int max_h = params.resize_height > 0 ? params.resize_height : params.resize_max;
      if (w > max_w || h > max_h) {
        double scale = std::min(
            static_cast<double>(max_w) / static_cast<double>(w),
            static_cast<double>(max_h) / static_cast<double>(h));
        out = img.resize(scale);
      }
      void* proc_buf = nullptr;
      size_t proc_len = 0;
      out.write_to_buffer(write_suffix.c_str(), &proc_buf, &proc_len);
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
    log_json("info", corr, "request path=/process");

    cpp_media::ParsedRequest parsed = cpp_media::parse_process_request(req);
    if (!parsed.parse_ok) {
      set_error_response(res, 400, parsed.error_code, parsed.error_message, corr);
      return;
    }
    if (parsed.image_bytes.empty()) {
      set_error_response(res, 400, "invalid_request", "No image data", corr);
      return;
    }

    cpp_media::ProcessParams params = cpp_media::resolve_profile(parsed.profile);
    std::string profile_used = parsed.profile.empty() ? "web_optimized" : parsed.profile;
    if (parsed.thumbnail_size >= 0) params.thumbnail_size = parsed.thumbnail_size;
    if (parsed.resize_max >= 0) params.resize_max = parsed.resize_max;
    if (parsed.width > 0) params.resize_width = parsed.width;
    if (parsed.height > 0) params.resize_height = parsed.height;
    if (parsed.quality > 0) params.jpeg_quality = parsed.quality;
    if (!parsed.output_format.empty()) params.output_format = parsed.output_format;
    if (!parsed.operations.empty()) {
      parse_operations(parsed.operations, params.want_thumbnail, params.want_resize);
    }

    std::string thumb_b64, thumb_ct, proc_b64, proc_ct, err;
    bool ok = process_image(parsed.image_bytes.data(),
                           parsed.image_bytes.size(),
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
    out << ",\"profile_used\":\"";
    for (char c : profile_used) {
      if (c == '"') out << "\\\"";
      else if (c == '\\') out << "\\\\";
      else out << c;
    }
    out << "\"";
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

  log_json("info", "", "listening on port " + std::to_string(port));
  if (!svr.listen("0.0.0.0", port)) {
    log_json("error", "", "Failed to listen on port " + std::to_string(port));
    vips_shutdown();
    return 1;
  }

  vips_shutdown();
  return 0;
}
