/*
 * cpp_media – request parser implementation.
 */

#include "request_parser.hpp"
#include "httplib.h"
#include <algorithm>
#include <cctype>
#include <string>

namespace cpp_media {

namespace {

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

int parse_int(const std::string& s, int default_val) {
  if (s.empty()) return default_val;
  try {
    return std::stoi(s);
  } catch (...) {
    return default_val;
  }
}

int get_json_int(const std::string& body, const char* key, int def) {
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
}

std::string get_json_str(const std::string& body, const char* key, const char* def) {
  std::string needle = std::string("\"") + key + "\":\"";
  size_t p = body.find(needle);
  if (p == std::string::npos) return std::string(def);
  p += needle.size();
  size_t q = body.find('"', p);
  if (q == std::string::npos) return std::string(def);
  return body.substr(p, q - p);
}

}  // namespace

ParsedRequest parse_process_request(const httplib::Request& req) {
  ParsedRequest out;
  out.parse_ok = false;

  if (req.form.has_file("file")) {
    const auto& file = req.form.get_file("file");
    out.image_bytes.assign(file.content.begin(), file.content.end());
    if (req.form.has_field("profile")) out.profile = req.form.get_field("profile");
    if (req.form.has_field("thumbnail_size")) {
      out.thumbnail_size = parse_int(req.form.get_field("thumbnail_size"), -1);
    }
    if (req.form.has_field("resize_max")) {
      out.resize_max = parse_int(req.form.get_field("resize_max"), -1);
    }
    if (req.form.has_field("width")) {
      out.width = parse_int(req.form.get_field("width"), 0);
    }
    if (req.form.has_field("height")) {
      out.height = parse_int(req.form.get_field("height"), 0);
    }
    if (req.form.has_field("quality")) {
      out.quality = parse_int(req.form.get_field("quality"), 0);
    }
    if (req.form.has_field("output_format")) {
      out.output_format = req.form.get_field("output_format");
    }
    if (req.form.has_field("operations")) {
      out.operations = req.form.get_field("operations");
    }
    out.parse_ok = !out.image_bytes.empty();
    if (!out.parse_ok) {
      out.error_code = "invalid_request";
      out.error_message = "No image data in file";
    }
    return out;
  }

  if (req.get_header_value("Content-Type").find("application/json") == std::string::npos) {
    out.error_code = "invalid_request";
    out.error_message = "Missing file or JSON body; use multipart file= or application/json with image_base64";
    return out;
  }

  const std::string& body = req.body;
  size_t pos = body.find("\"image_base64\"");
  if (pos == std::string::npos) {
    out.error_code = "invalid_request";
    out.error_message = "Missing image_base64 in JSON";
    return out;
  }
  pos = body.find(':', pos);
  if (pos == std::string::npos) {
    out.error_code = "invalid_request";
    out.error_message = "Invalid JSON";
    return out;
  }
  pos = body.find('"', pos + 1);
  if (pos == std::string::npos) {
    out.error_code = "invalid_request";
    out.error_message = "Invalid JSON";
    return out;
  }
  size_t start = pos + 1;
  size_t end = body.find('"', start);
  if (end == std::string::npos) end = body.size();
  std::string b64 = body.substr(start, end - start);
  out.image_bytes = base64_decode(b64);
  if (out.image_bytes.empty()) {
    out.error_code = "invalid_request";
    out.error_message = "Invalid or empty image_base64";
    return out;
  }

  out.profile = get_json_str(body, "profile", "");
  out.thumbnail_size = get_json_int(body, "thumbnail_size", -1);
  out.resize_max = get_json_int(body, "resize_max", -1);
  out.width = get_json_int(body, "width", 0);
  out.height = get_json_int(body, "height", 0);
  out.quality = get_json_int(body, "quality", 0);
  out.output_format = get_json_str(body, "output_format", "");
  out.operations = get_json_str(body, "operations", "");
  out.parse_ok = true;
  return out;
}

}  // namespace cpp_media
