require 'spec_helper'
require 'socket'

describe 'event handler' do
  %w(villein-event-handler villein-event-handler.rb).each do |handler_name|
    _handler = File.join(__dir__, '..', 'misc', handler_name)
    opts = File.exist?(_handler) ? {} : {pending: "#{handler_name} not exists"}
    describe handler_name, opts do
      let(:handler) { _handler }

      def run_handler(env: {'SERF_EVENT' => 'user', 'SERF_USER_EVENT' => 'test'}, input: nil, response: nil)
        serv = TCPServer.new('localhost', 0)
        sockout = nil
        serv_thread = Thread.new do
          begin
            sock = serv.accept

            sockout = sock.read
            sock.write response if response
            sock.close_write
          ensure
            sock.close if sock && !sock.closed?
            serv.close if serv && !serv.closed?
          end
        end
        serv_thread.abort_on_exception = true

        stdout = nil
        IO.popen([env, handler, serv.addr[-1].to_s, serv.addr[1].to_s], 'r+') do |io|
          io.write(input) if input
          io.close_write
          stdout = io.read
          Process.waitpid2 io.pid
        end

        serv_thread.join
        return stdout, sockout
      end

      it "reports environment variables" do
        stdout, sockout = run_handler
        expect(sockout).to include("SERF_EVENT=user\0")
        expect(sockout).to include("SERF_USER_EVENT=test\0")
        expect(sockout).to match(/(user|test)\0\0\z/)
      end

      it "pass stdin to socket" do
        stdout, sockout = run_handler(input: "foo\n")
        expect(sockout).to include("SERF_EVENT=user\0")
        expect(sockout).to match(/(user|test)\0\0foo\n\z/m)
      end

      context "if SERF_EVENT=query" do
        it "pass socket input to stdout" do
          stdout, sockout = run_handler(env: {'SERF_EVENT' => 'query'}, input: "foo\n", response: "bar\n")
          expect(sockout).to match(/SERF_EVENT=query\0\0foo\n\z/m)
          expect(stdout).to eq("bar\n")
        end
      end
    end
  end
end
