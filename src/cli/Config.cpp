#include <cli/Config.hpp>

#include <rubr/fs/util.hpp>

namespace cli {

    ReturnCode Config::init(const Options &options)
    {
        MSS_BEGIN(ReturnCode);

        {
            auto &grove = groves.emplace_back();
            grove.name = "am";
            grove.root = rubr::fs::expand_path("~/am");
            grove.extensions = {"md", "txt", "rb", "hpp", "cpp", "h", "c", "chai"};
            // grove.max_size = 256000;
        }

        // Prepend a '.' for the extensions where necessary
        for (auto &grove : groves)
        {
            std::vector<std::string> exts;
            for (std::string ext : grove.extensions)
            {
                if (ext.empty())
                    continue;
                if (ext[0] != '.')
                    ext = "."+ext;
                if (std::find(exts.begin(), exts.end(), ext) == exts.end())
                    exts.push_back(ext);
            }
            std::swap(grove.extensions, exts);
        }

        MSS_END();
    }

} // namespace cli
