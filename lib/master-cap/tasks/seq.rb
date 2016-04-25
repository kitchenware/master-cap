
Capistrano::Configuration.instance.load do

  module Capistrano
    class Configuration
      module Connections
        alias_method :execute_on_servers_old, :execute_on_servers

        def execute_on_servers options={}, &block
          execute_on_servers_old options do |l|
            if exists? :run_seq
              l.each do |x|
                block.call [x]
              end
            elsif exists? :run_batch
              batch_size = fetch(:run_batch)
              l.each_slice(batch_size) do |l2|
                block.call l2
              end
            else
              block.call l
            end
          end
        end
      end
    end
  end

end