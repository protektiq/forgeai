/*
 * cpp_media – processing profile registry.
 * Defines named profiles (thumbnail_square, web_optimized, high_quality_jpg)
 * and resolves profile name + overrides to ProcessParams.
 */

#ifndef CPP_MEDIA_PROFILES_HPP
#define CPP_MEDIA_PROFILES_HPP

#include <string>

namespace cpp_media {

struct ProcessParams {
  int thumbnail_size = 256;
  int resize_max = 1200;
  std::string output_format = "jpg";
  bool want_thumbnail = true;
  bool want_resize = true;
  int jpeg_quality = 0;       /* 0 = libvips default */
  int resize_width = 0;       /* 0 = use resize_max for scaling */
  int resize_height = 0;
};

/* Resolve profile name to default ProcessParams. Unknown/empty returns web_optimized. */
ProcessParams resolve_profile(const std::string& profile_name);

}  // namespace cpp_media

#endif
