/*
 * cpp_media – request parser for POST /process.
 * Parses multipart or JSON body into a single struct; does not resolve profiles or call vips.
 */

#ifndef CPP_MEDIA_REQUEST_PARSER_HPP
#define CPP_MEDIA_REQUEST_PARSER_HPP

#include <string>
#include <vector>

namespace httplib {
struct Request;
}

namespace cpp_media {

struct ParsedRequest {
  std::vector<unsigned char> image_bytes;
  std::string profile;
  int thumbnail_size = -1;   /* -1 = not set, use profile default */
  int resize_max = -1;
  int width = 0;            /* 0 = not set */
  int height = 0;
  int quality = 0;           /* 0 = not set */
  std::string output_format;
  std::string operations;
  bool parse_ok = false;
  std::string error_code;
  std::string error_message;
};

/* Parse req (multipart or JSON). On success parse_ok is true and image_bytes is non-empty. */
ParsedRequest parse_process_request(const httplib::Request& req);

}  // namespace cpp_media

#endif
