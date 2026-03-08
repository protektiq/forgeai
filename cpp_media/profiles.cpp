/*
 * cpp_media – profile registry implementation.
 */

#include "profiles.hpp"
#include <algorithm>
#include <cctype>

namespace cpp_media {

namespace {

std::string to_lower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return s;
}

}  // namespace

ProcessParams resolve_profile(const std::string& profile_name) {
  std::string name = to_lower(profile_name);
  /* Trim leading/trailing whitespace */
  while (!name.empty() && std::isspace(static_cast<unsigned char>(name.back()))) name.pop_back();
  size_t start = 0;
  while (start < name.size() && std::isspace(static_cast<unsigned char>(name[start]))) start++;
  if (start > 0) name = name.substr(start);

  if (name == "thumbnail_square") {
    ProcessParams p;
    p.thumbnail_size = 256;
    p.resize_max = 1200;
    p.output_format = "jpg";
    p.want_thumbnail = true;
    p.want_resize = false;
    p.jpeg_quality = 0;
    return p;
  }
  if (name == "web_optimized") {
    ProcessParams p;
    p.thumbnail_size = 256;
    p.resize_max = 1200;
    p.output_format = "jpg";
    p.want_thumbnail = true;
    p.want_resize = true;
    p.jpeg_quality = 85;
    return p;
  }
  if (name == "high_quality_jpg") {
    ProcessParams p;
    p.thumbnail_size = 256;
    p.resize_max = 2400;
    p.output_format = "jpg";
    p.want_thumbnail = true;
    p.want_resize = true;
    p.jpeg_quality = 92;
    return p;
  }
  /* Default: web_optimized for unknown or empty */
  ProcessParams p;
  p.thumbnail_size = 256;
  p.resize_max = 1200;
  p.output_format = "jpg";
  p.want_thumbnail = true;
  p.want_resize = true;
  p.jpeg_quality = 85;
  return p;
}

}  // namespace cpp_media
