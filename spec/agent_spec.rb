require 'spec_helper'
require 'villein/client'

require 'villein/agent'

describe Villein::Agent do
  it "inherits Villein::Client" do
    expect(described_class.ancestors).to include(Villein::Client)
  end

  let(:bind)     { ENV["VILLEIN_TEST_BIND"]     || "127.0.0.1:17946" }
  let(:rpc_addr) { ENV["VILLEIN_TEST_RPC_ADDR"] || "127.0.0.1:17373" }

  subject(:agent) { described_class.new(rpc_addr: rpc_addr, bind: bind) }

  before do
    @pids = []
    allow(agent).to(receive(:spawn) { |*args|
      pid = Kernel.spawn(*args)
      @pids << pid
      pid
    })
  end

  after do
    @pids.each do |pid|
      begin
        begin
          timeout(5) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill(:KILL, pid)
        end
      rescue Errno::ECHILD, Errno::ESRCH
      end
    end
  end

  it "can start and stop workers" do
    received = nil
    agent.on_stop { |arg| received = [true, arg] }

    agent.start!

    expect(agent.dead?).to be_false
    expect(agent.running?).to be_true
    expect(agent.started?).to be_true
    expect(agent.pid).to be_a(Fixnum)

    agent.stop!

    expect(agent.dead?).to be_false
    expect(agent.running?).to be_false
    expect(agent.started?).to be_false
    expect(agent.pid).to be_nil

    expect(received).to eq [true, nil]
  end

  it "can receive events" do
    received1, received2 = nil, nil

    agent.on_event { |e| received1 = e }
    agent.on_member_join { |e| received2 = e }

    agent.start!
    20.times { break if received1; sleep 0.1 }
    agent.stop!

    expect(received1).to be_a(Villein::Event)
    expect(received2).to be_a(Villein::Event)
    expect(received1.type).to eq 'member-join'
    expect(received2.type).to eq 'member-join'
  end

  it "can handle unexpected stop" do
    received = nil
    agent.on_stop { |status| received = status }

    agent.start!
    Process.kill(:KILL, agent.pid)

    20.times { break if received; sleep 0.1 }
    expect(agent.dead?).to be_true
    expect(agent.running?).to be_false
    expect(agent.started?).to be_true
    expect(received).to be_a_kind_of(Process::Status)
  end
end
