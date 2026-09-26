// cli_converter.cpp - standalone command-line converter.
//
// Lets you test the ported conversion core WITHOUT Qt or RAD Studio.
// Builds with any C++17 compiler that can reach zlib and bcrypt (the reader
// needs both for the encrypted containers) - see tools\build_cli.bat, which
// uses the MinGW-w64 g++ from the Qt toolchain.
//
// Usage:
//   AvroConvertCLI.exe <direction> <mapping> <input.txt> <output.txt> [--bench]
//     direction : "u2a" (Unicode -> ANSI) or "a2u" (ANSI -> Unicode)
//     mapping   : "Ansi V3" | "SutonnyMJ" | "BanglaPedia v1.3"
//     --bench   : also print wall-clock conversion time and Peak RSS (Windows)
//
// The ANSI mappings are auto-loaded from the system-wide Avro Keyboard
// installation (C:\ProgramData\Avro Keyboard\AnsiMapping), where they ship as
// encrypted .AvroEnco containers that the shared reader decrypts in memory.
#include <chrono>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
// MSVC links psapi automatically; MinGW builds need -lpsapi.
#pragma comment(lib, "psapi.lib")
#endif

#include "ansi_registry.h"
#include "unicode_to_bijoy.h"
#include "bijoy_to_unicode.h"

static double peakRssMb() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        return pmc.PeakWorkingSetSize / (1024.0 * 1024.0);
#endif
    return 0.0;
}

static std::wstring readUtf8File(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    std::vector<char> buf((std::istreambuf_iterator<char>(in)),
                          std::istreambuf_iterator<char>());
    if (buf.size() >= 3 && (unsigned char)buf[0] == 0xEF &&
        (unsigned char)buf[1] == 0xBB && (unsigned char)buf[2] == 0xBF)
        buf.erase(buf.begin(), buf.begin() + 3);
    std::wstring out;
    out.reserve(buf.size());
    size_t i = 0;
    while (i < buf.size()) {
        unsigned char c = (unsigned char)buf[i];
        if (c < 0x80) {
            out += (wchar_t)c;
            i += 1;
        } else if ((c >> 5) == 0x6) {
            out += (wchar_t)(((c & 0x1F) << 6) | (buf[i + 1] & 0x3F));
            i += 2;
        } else if ((c >> 4) == 0xE) {
            out += (wchar_t)(((c & 0x0F) << 12) | ((buf[i + 1] & 0x3F) << 6) |
                             (buf[i + 2] & 0x3F));
            i += 3;
        } else {
            out += (wchar_t)(((c & 0x07) << 18) | ((buf[i + 1] & 0x3F) << 12) |
                             ((buf[i + 2] & 0x3F) << 6) | (buf[i + 3] & 0x3F));
            i += 4;
        }
    }
    return out;
}

static void writeUtf8File(const std::string& path, const std::wstring& s) {
    std::ofstream out(path, std::ios::binary);
    for (wchar_t ch : s) {
        unsigned cp = (unsigned)ch;
        if (cp < 0x80) {
            out.put((char)cp);
        } else if (cp < 0x800) {
            out.put((char)(0xC0 | (cp >> 6)));
            out.put((char)(0x80 | (cp & 0x3F)));
        } else {
            out.put((char)(0xE0 | (cp >> 12)));
            out.put((char)(0x80 | ((cp >> 6) & 0x3F)));
            out.put((char)(0x80 | (cp & 0x3F)));
        }
    }
}

static std::string findAnsiMappingDir() {
    return "C:/ProgramData/Avro Keyboard/AnsiMapping/";
}

int main(int argc, char** argv) {
    if (argc < 5) {
        std::fprintf(stderr,
            "Avro Convert CLI - ported converter core (no Qt needed).\n\n"
            "Usage:\n"
            "  %s <direction> <mapping> <input.txt> <output.txt> [--bench]\n\n"
            "  direction : \"u2a\" (Unicode -> ANSI) or \"a2u\" (ANSI -> Unicode)\n"
            "  mapping   : \"Ansi V3\" | \"SutonnyMJ\" | \"BanglaPedia v1.3\"\n"
            "  --bench   : also print wall-clock time and Peak RSS\n\n"
            "Example:\n"
            "  %s u2a \"Ansi V3\" input.txt output.txt --bench\n",
            argc > 0 ? argv[0] : "AvroConvertCLI",
            argc > 0 ? argv[0] : "AvroConvertCLI");
        return 2;
    }

    const std::string dir = argv[1];
    const std::string mapping = argv[2];
    const std::string inPath = argv[3];
    const std::string outPath = argv[4];
    const bool bench = argc > 5 && std::string(argv[5]) == "--bench";

    avro::g_registry.init();
    const std::string adir = findAnsiMappingDir();
    avro::g_registry.ansiMappingDir = std::wstring(adir.begin(), adir.end());
    std::wstring err;
    if (!avro::g_registry.trySetAnsiVersion(std::wstring(mapping.begin(), mapping.end()), err)) {
        std::fprintf(stderr, "Failed to load mapping '%s': %ls\n",
                     mapping.c_str(), err.c_str());
        return 1;
    }

    std::wstring input = readUtf8File(inPath);
    std::wstring output;

    const auto t0 = std::chrono::high_resolution_clock::now();
    if (dir == "u2a") {
        avro::UnicodeToBijoy conv;
        output = conv.convert(input);
    } else if (dir == "a2u") {
        avro::BijoyToUnicode conv;
        output = conv.convert(input);
    } else {
        std::fprintf(stderr, "Unknown direction '%s' (use u2a or a2u).\n", dir.c_str());
        return 1;
    }
    const auto t1 = std::chrono::high_resolution_clock::now();

    writeUtf8File(outPath, output);
    if (bench) {
        const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
        std::printf("OK: %zu chars -> %zu chars | Time: %.0f ms | Peak RSS: %.1f MB\n",
                    input.size(), output.size(), ms, peakRssMb());
    } else {
        std::printf("OK: %zu chars -> %zu chars\n", input.size(), output.size());
    }
    return 0;
}
