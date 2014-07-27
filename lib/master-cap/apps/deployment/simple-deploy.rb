
Capistrano::Configuration.instance.load do

	load 'deploy'

	require_relative 'common.rb'

	namespace :deploy do

		task :finalize_update do
		end

	end

end