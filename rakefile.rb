require('fileutils')

here_dir = File.dirname(__FILE__)
gubg_dir = ENV['gubg']
gubg_bin_dir = File.join(gubg_dir, 'bin')

task :default do
    sh 'rake -T'
end

desc 'Install'
task :install, :variant do |_task, args|
    variant = args[:variant]&.to_sym || :zig

    mode = :safe
    mode = :fast
    # mode = :debug

    case variant
    when :zig
        m = { safe: :safe, fast: :fast }[mode]
        mode_str = m ? "--release=#{m}" : ''
        sh("clear")
        sh("zig build install #{mode_str} --prefix-exe-dir #{gubg_bin_dir} -freference-trace=10")
    when :cpp
        m = { safe: :release, fast: :release }[mode] || :release
        sh("xmake f -m #{m}")
        sh('xmake build -v champ')
        fp = "build/linux/x86_64/#{m}/champ"
        FileUtils.cp(fp, gubg_bin_dir)
    when :rust
        profile = { safe: 'release-with-debug', fast: 'release', debug: 'debug' }[mode]
        sh "cargo install --path . --profile #{profile} --root #{gubg_dir}"
        # sh "cargo package"
        # sh "cargo publish"
    else raise("Unknown variant #{variant}")
    end
end

desc 'Run'
task :run, %i[extra mode] do |_task, args|
    mode = args[:mode]&.to_sym || :release
    sh("xmake f -m #{mode}")
    sh('xmake build -v ampp')

    sh("xmake run ampp #{args[:extra]}")
end

desc 'Run all UTs'
task :ut, %i[filter] do |_task, args|
    sh "clear"

    filter = (args[:filter] || '').split(':').map { |e| "-Dtest-filter=#{e}" } * ' '
    sh "zig build test #{filter} -freference-trace=10"

    mode = :release
    # mode = :debug
    # sh("xmake f -c") # This was needed once to make xmake detect the local toolchains
    sh("xmake f -m #{mode}")
    sh('xmake build -v amplib_ut')
    sh('xmake run amplib_ut')

    unless :rust
        # sh 'cargo test -- --nocapture --test-threads 1 lex'
        sh 'cargo test -- --nocapture --test-threads 1'
    end
end

desc('Clean')
task :clean do
    sh('xmake clean')
    FileUtils.rm_rf('target')
    FileUtils.rm_rf('zig-out')
end

desc('Generate .clangd file')
task :clangd do
    File.open('.clangd', 'w') do |fo|
        fo.puts('CompileFlags:')
        # &shortcut: How can I get the include path for catch2 from xmake?
        include_dirs = %w[src ext/rubr/src
                          /home/geertf/.xmake/packages/c/catch2/v3.8.0/39d7db50b8e54e09ac555b3ca94b3a17/include].map do |dir|
            "-I#{dir[0] == '/' ? dir : File.join(here_dir, dir)}"
        end
        fo.puts("    Add: [-std=c++23, #{include_dirs * ', '}]")
    end
end
