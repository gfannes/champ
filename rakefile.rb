task :default do
    sh 'rake -T'
end

task :prepare do
    gubg = ENV['gubg']
    raise("Env var 'gubg' not set") unless gubg

    sh "ln -s #{gubg} gubg" unless File.exist?('gubg')

    require_relative('gubg/gubg.build/load.rb')
    require('gubg/build/Cooker')
end

desc 'Build the targets'
task :build => :prepare do
    cooker = Gubg::Build::Cooker.new()
    cooker.generate(:ninja, 'champetter/cli').ninja()
end

desc 'Install the CLI application'
task :install => :build do
    sh 'sudo cp champetter.cli /usr/local/bin/champ'
end

desc 'Run the unit tests'
task :ut => :prepare do
    cooker = Gubg::Build::Cooker.new()
    cooker.generate(:ninja, 'champetter/ut').ninja()
    sh './champetter.ut'
end

desc 'Run the e2e tests'
task :e2e => :build do
end
