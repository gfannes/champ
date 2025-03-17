#include <cli/Config.hpp>

#include <rubr/fs/util.hpp>

namespace cli {

    ReturnCode Config::init(const Options &options)
    {
        MSS_BEGIN(ReturnCode);

        auto use_grove = [&](const std::string_view &name) {
            auto it = std::find_if(options.groves.begin(), options.groves.end(), [&](const auto &str) {return name == str;});
            return it != options.groves.end();
        };

        {
            Grove grove;
            grove.name = "am";
            grove.root = rubr::fs::expand_path("~/auro/master");
            grove.extensions = {"md", "txt", "rb", "hpp", "cpp", "h", "c", "chai"};
            grove.max_size = 256000;
            if (use_grove(grove.name))
                groves.push_back(grove);
        }

        {
            Grove grove;
            grove.name = "amdebug";
            grove.root = rubr::fs::expand_path("~/auro/master");
            grove.extensions = {"md", "txt", "rb", "hpp", "cpp", "h", "c", "chai"};
            grove.max_size = 256000;
            grove.count = 1;
            if (use_grove(grove.name))
                groves.push_back(grove);
        }

        {
            Grove grove;
            grove.name = "amall";
            grove.root = rubr::fs::expand_path("~/auro/master");
            // grove.extensions = {"md", "txt", "rb", "hpp", "cpp", "h", "c", "chai"};
            // grove.max_size = 256000;
            // grove.count = 1;
            if (use_grove(grove.name))
                groves.push_back(grove);
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
                    ext = "." + ext;
                if (std::find(exts.begin(), exts.end(), ext) == exts.end())
                    exts.push_back(ext);
            }
            std::swap(grove.extensions, exts);
        }

        MSS_END();
    }

} // namespace cli
