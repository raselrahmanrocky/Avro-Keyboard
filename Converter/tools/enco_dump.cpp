// enco_dump.cpp - dev tool: decode an .AvroEnco mapping container to JSON.
//
//   enco_dump <container.AvroEnco> [out.json]
//
// Prints the decoded JSON size (or the failure reason) and writes the JSON to
// out.json when given.  It links the same reader the GUI uses, so a container
// that decodes here decodes in the application.
//
// Build (MinGW, from the repository root - no Qt required):
//
//   g++ -std=c++17 -O2 -o tools/enco_dump.exe tools/enco_dump.cpp
//       src/core/avroenco_reader.cpp -lbcrypt -lz -ladvapi32
//
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "core/avroenco_reader.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: enco_dump <container.AvroEnco> [out.json]\n");
        return 2;
    }
    std::ifstream in(argv[1], std::ios::binary);
    if (!in.good()) {
        std::fprintf(stderr, "cannot open %s\n", argv[1]);
        return 2;
    }
    const std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(in)),
                                           std::istreambuf_iterator<char>());

    std::string json;
    std::string error;
    if (!avro::decodeAvroEncoContainer(bytes.data(), bytes.size(), std::string(),
                                       json, error)) {
        std::fprintf(stderr, "%s: FAILED - %s\n", argv[1], error.c_str());
        return 1;
    }
    std::printf("%s: ok, %zu bytes of JSON\n", argv[1], json.size());
    if (argc >= 3) {
        std::ofstream out(argv[2], std::ios::binary);
        out.write(json.data(), static_cast<std::streamsize>(json.size()));
        std::printf("  written to %s\n", argv[2]);
    }
    return 0;
}
