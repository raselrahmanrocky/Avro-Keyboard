#include "sweep_table.h"

#include <algorithm>
#include <cwctype>

namespace avro {

SweepTable::SweepTable(const std::vector<SweepEntry>& entries) {
    allSingle_ = true;
    for (const auto& e : entries) {
        if (!e.key.empty() && e.key.size() != 1) {
            allSingle_ = false;
            break;
        }
    }

    if (allSingle_) {
        single_.reserve(entries.size());
        for (const auto& e : entries)
            if (!e.key.empty())
                single_[e.key[0]] = e.value;
        return;
    }

    // Bucket keys by their first character; sort each bucket longest-first.
    // Uses a sparse map — only characters that appear as first-key-char
    // get a bucket, saving ~3 MB vs. a fixed 65536-element vector.
    for (const auto& e : entries) {
        if (e.key.empty())
            continue;
        buckets_[e.key[0]].entries.push_back(e);
    }
    for (auto& [ch, bucket] : buckets_) {
        std::stable_sort(bucket.entries.begin(), bucket.entries.end(),
                         [](const SweepEntry& l, const SweepEntry& r) {
                             return l.key.size() > r.key.size();
                         });
    }
}

SweepTable::~SweepTable() {}

bool SweepTable::matchAt(const std::wstring& s, size_t i, std::wstring& outValue,
                         size_t& outKeyLen) const {
    // Delphi parity: the original MatchAt exits when FBuckets is nil, and an
    // all-single-char table keeps FBuckets nil - so MatchAt (used only by
    // ApplyKarInclusiveFullForms) reports no match for single-char tables.
    if (allSingle_)
        return false;
    if (i >= s.size())
        return false;
    auto bit = buckets_.find(s[i]);
    if (bit == buckets_.end() || bit->second.entries.empty())
        return false;
    const Bucket& bucket = bit->second;
    for (const auto& e : bucket.entries) {
        const std::wstring& k = e.key;
        if (i + k.size() > s.size())
            continue;
        // First char matched by the bucket; check the rest.
        if (s.compare(i + 1, k.size() - 1, k, 1, k.size() - 1) == 0) {
            outValue = e.value;
            outKeyLen = k.size();
            return true;
        }
    }
    return false;
}

std::wstring SweepTable::sweep(const std::wstring& s) const {
    if (s.empty())
        return s;
    std::wstring out;
    out.reserve(s.size() + 16);
    size_t n = s.size();
    size_t i = 0;

    if (allSingle_) {
        while (i < n) {
            auto it = single_.find(s[i]);
            if (it != single_.end()) {
                out.append(it->second);
                ++i;
            } else {
                // Bulk-append the run of non-matching characters.
                size_t start = i;
                do {
                    ++i;
                } while (i < n && single_.find(s[i]) == single_.end());
                out.append(s, start, i - start);
            }
        }
    } else {
        while (i < n) {
            std::wstring v;
            size_t klen = 0;
            if (matchAt(s, i, v, klen)) {
                out.append(v);
                i += klen;
            } else {
                // Bulk-append the run of positions whose bucket is empty.
                size_t start = i;
                do {
                    ++i;
                } while (i < n && buckets_.find(s[i]) == buckets_.end());
                out.append(s, start, i - start);
            }
        }
    }
    return out;
}

void SweepTable::sweepInPlace(std::wstring& s) const {
    if (s.empty())
        return;

    // NOT literally in-place: std::wstring::replace() shifts the whole tail
    // of the buffer on every hit, which is O(n) per match and O(n^2) overall
    // when a key occurs densely (e.g. re-joining every split ো/ৌ in a
    // multi-megabyte document).  Build the result in a fresh buffer and swap
    // it in - one linear pass, one copy.
    std::wstring out;
    out.reserve(s.size() + 16);
    const size_t n = s.size();
    size_t i = 0;

    if (allSingle_) {
        while (i < n) {
            auto it = single_.find(s[i]);
            if (it != single_.end()) {
                out.append(it->second);
                ++i;
            } else {
                // Bulk-append the run of non-matching characters.
                size_t start = i;
                do {
                    ++i;
                } while (i < n && single_.find(s[i]) == single_.end());
                out.append(s, start, i - start);
            }
        }
    } else {
        while (i < n) {
            std::wstring v;
            size_t klen = 0;
            if (matchAt(s, i, v, klen)) {
                out.append(v);
                i += klen;
            } else {
                // Bulk-append the run of positions whose bucket is empty.
                size_t start = i;
                do {
                    ++i;
                } while (i < n && buckets_.find(s[i]) == buckets_.end());
                out.append(s, start, i - start);
            }
        }
    }
    s.swap(out);
}

std::wstring replaceStr(const std::wstring& s, const std::wstring& from,
                        const std::wstring& to) {
    if (from.empty())
        return s;
    std::wstring out;
    size_t pos = 0;
    while (pos < s.size()) {
        size_t hit = s.find(from, pos);
        if (hit == std::wstring::npos) {
            out.append(s, pos, s.size() - pos);
            break;
        }
        out.append(s, pos, hit - pos);
        out.append(to);
        pos = hit + from.size();
    }
    return out;
}

} // namespace avro
