require 'spec_helper'
require 'villein/client'

describe Villein::Client do
  let(:name) { 'the-node' }
  subject(:client) { described_class.new('x.x.x.x:nnnn', name: name) }

  def expect_serf(cmd, *args, retval: true, out: File::NULL)
    expect(subject).to receive(:system) \
      .with('serf', cmd, '-rpc-addr=x.x.x.x:nnnn', *args, out: out, err: out) \
      .and_return(retval)
  end

  describe "#event" do
    it "sends user event" do
      expect_serf('event', 'test', 'payload')

      client.event('test', 'payload')
    end

    context "with coalesce=false" do
      it "sends user event with the option" do
        expect_serf('event', '-coalesce=false', 'test', 'payload')

        client.event('test', 'payload', coalesce: false)
      end
    end
  end

  describe "#join" do
    it "attempts to join another node" do
      expect_serf('join', 'y.y.y.y:nnnn')

      client.join('y.y.y.y:nnnn')
    end

    context "with replay=true" do
      it "attempts to join another node with replaying" do
        expect_serf('join', '-replay', 'y.y.y.y:nnnn')

        client.join('y.y.y.y:nnnn', replay: true)
      end
    end
  end

  describe "#leave" do
    it "attempts to leave from cluster" do
      expect_serf('leave')

      client.leave
    end
  end

  describe "#force_leave" do
    it "attempts to remove member forcely" do
      expect_serf('force-leave', 'the-node')

      client.force_leave('the-node')
    end
  end

  describe "#members" do
    let(:json) { (<<-EOJ).gsub(/\n|\s+/,'') }
    {"members":[{"name":"the-node","addr":"a.a.a.a:mmmm","port": 7948,
    "tags":{"key":"val"},"status":"alive","protocol":{"max":4,"min":2,"version":4}}]}
    EOJ

    it "returns member list" do
      allow(IO).to receive(:popen).with(%w(serf members -rpc-addr=x.x.x.x:nnnn -format json), 'r') \
        .and_yield(double('io', read: json))

      expect(client.members).to be_a_kind_of(Array)
      expect(client.members[0]["name"]).to eq "the-node"
    end

    context "with status filter" do
      it "returns member list" do
        allow(IO).to receive(:popen).with(%w(serf members -rpc-addr=x.x.x.x:nnnn -format json -status alive), 'r') \
          .and_yield(double('io', read: json))

        client.members(status: :alive)
      end
    end

    context "with name filter" do
      it "returns member list" do
        allow(IO).to receive(:popen).with(%w(serf members -rpc-addr=x.x.x.x:nnnn -format json -name node), 'r') \
          .and_yield(double('io', read: json))

        client.members(name: 'node')
      end
    end

    context "with tag filter" do
      it "returns member list" do
        allow(IO).to receive(:popen).with(%w(serf members -rpc-addr=x.x.x.x:nnnn -format json -tag a=1 -tag b=2), 'r') \
          .and_yield(double('io', read: json))

        client.members(tags: {a: '1', b: '2'})
      end
    end
  end

  describe "#tags" do
    before do
      allow(client).to receive(:get_tags).and_return('a' => 'b')
    end

    it "returns Villein::Tags" do
      expect(client.tags).to be_a(Villein::Tags)
      expect(client.tags['a']).to eq 'b'
    end

    it "memoizes" do
      expect(client.tags.__id__ == client.tags.__id__).to be_true
    end
  end

  describe "#set_tag" do
    it "sets tag" do
      expect_serf('tags', '-set', 'newkey=newval')

      client.set_tag('newkey', 'newval')
    end
  end

  describe "#delete_tag" do
    it "deletes tag" do
      expect_serf('tags', '-delete', 'newkey')

      client.delete_tag('newkey')
    end
  end

  describe "#get_tags" do
    subject(:tags) { client.get_tags }

    it "retrieves using #member(name: )" do
      json = (<<-EOJ).gsub(/\n|\s+/,'')
        {"members":[{"name":"the-node","addr":"a.a.a.a:mmmm","port": 7948,
        "tags":{"key":"val"},"status":"alive","protocol":{"max":4,"min":2,"version":4}}]}
      EOJ

      allow(IO).to receive(:popen).with(%w(serf members -rpc-addr=x.x.x.x:nnnn -format json -name the-node), 'r') \
        .and_yield(double('io', read: json))

      expect(tags).to be_a_kind_of(Hash)
      expect(tags['key']).to eq 'val'
    end

    context "without name" do
      let(:name) { nil }

      it "raises error" do
        expect { tags }.to raise_error
      end
    end
  end
end

