require 'spec_helper'
require 'villein/client'

describe Villein::Client do
  let(:name) { 'the-node' }
  subject(:client) { described_class.new('x.x.x.x:nnnn', name: name) }

  def expect_serf(cmd, *args, success: true, message: '')
    if [cmd, *args].compact.empty?
      expect(IO).to receive(:popen) \
        .with(any_args)
        .and_yield(double('io', read: message, pid: 727272))

    else
      expect(IO).to receive(:popen) \
        .with(['serf', cmd, '-rpc-addr=x.x.x.x:nnnn', *args,
               err: [:child, :out]],
              'r') \
        .and_yield(double('io', read: message, pid: 727272))
    end

    status = double('proc-status', pid: 727272, success?: success)

    allow(Process).to receive(:waitpid2).with(727272).and_return([727272, status])
  end

  shared_examples "failure cases" do
    context "when command failed" do
      it "raises error" do
        expect_serf(nil, success: false, message: 'err')

        expect {
          subject
        }.to raise_error(Villein::Client::SerfError, 'err')
      end
    end

    context "when connection failed" do
      it "raises error" do
        expect_serf(nil,
          success: false,
          message: 'Error connecting to Serf agent: dial tcp x.x.x.x:nnnn: connection refused')

        expect {
          subject
        }.to raise_error(
          Villein::Client::SerfConnectionError,
          'Error connecting to Serf agent: dial tcp x.x.x.x:nnnn: connection refused')
      end
    end
  end

  describe "#initialize" do
    context "without name" do
      subject(:client) { described_class.new('x.x.x.x:nnnn') }

      it "retrieves name using #info" do
        # we can't use allow(client) here because it calls #initialize!
        allow_any_instance_of(described_class).to receive(:info).and_return(
          "agent" => {"name" => "the-name"},
        )

        expect(client.name).to eq('the-name')
      end
    end
  end

  describe "#info" do
    let(:json) { (<<-EOJ).gsub(/\n|\s+/,'') }
    {
      "agent": {
        "name": "foo"
      },
      "runtime": {
        "arch": "amd64",
        "cpu_count": "8",
        "goroutines": "22",
        "max_procs": "1",
        "os": "darwin",
        "version": "go1.2"
      },
      "serf": {
        "event_queue": "0",
        "event_time": "1",
        "failed": "0",
        "intent_queue": "0",
        "left": "0",
        "member_time": "2",
        "members": "2",
        "query_queue": "0",
        "query_time": "3"
      },
      "tags": {
        "thisis": "tag"
      }
    }
    EOJ

    subject(:info) { client.info }

    it "returns `serf info`" do
      expect_serf('info', '-format', 'json', message: json)

      expect(info).to eq(JSON.parse(json))
    end

    context "when not available" do
      it "raises error" do
        expect_serf('info', '-format', 'json', message: 'Available commands are:', success: false)

        expect { info }.to raise_error(Villein::Client::InsufficientVersionError)
      end
    end

    include_examples "failure cases"
  end

  describe "#event" do
    subject { client.event('test', 'payload') }

    it "sends user event" do
      expect_serf('event', 'test', 'payload')

      subject
    end

    context "with coalesce=false" do
      subject { client.event('test', 'payload', coalesce: false) }

      it "sends user event with the option" do
        expect_serf('event', '-coalesce=false', 'test', 'payload')

        subject
      end
    end

    include_examples "failure cases"

    context "when length exceeds limit" do
      it "raises error" do
        expect_serf('event', 'test', 'payload',
          success: false,
          message: 'Error sending event: user event exceeds limit of 256 bytes')

        expect {
          subject
        }.to raise_error(
          Villein::Client::LengthExceedsLimitError,
          'Error sending event: user event exceeds limit of 256 bytes')
      end
    end
  end

  describe "#query" do
    let(:json) { (<<-EOJ).gsub(/\n|\s+/,'') }
      {"Acks":["foo","bar"], "Responses":{"foo":"response"}}
    EOJ

    subject(:query) { client.query('test', 'payload') }

    it "sends query event" do
      expect_serf('query', '-format', 'json', 'test', 'payload', message: json)

      expect(query).to eq(JSON.parse(json))
    end

    context "with node filter" do
      context "in String" do
        subject(:query) { client.query('test', 'payload', node: 'foo') }

        it "queries with -node" do
          expect_serf('query', '-format', 'json', '-node=foo', 'test', 'payload', message: json)
          query
        end
      end

      context "in Array" do
        subject(:query) { client.query('test', 'payload', node: %w(foo bar)) }

        it "queries with -node" do
          expect_serf('query', '-format', 'json', '-node=foo', '-node=bar', 'test', 'payload', message: json)
          query
        end
      end
    end

    context "with tag filter" do
      context "in String" do
        subject(:query) { client.query('test', 'payload', tag: 'foo') }

        it "queries with -tag" do
          expect_serf('query', '-format', 'json', '-tag=foo', 'test', 'payload', message: json)
          query
        end
      end

      context "in Array" do
        subject(:query) { client.query('test', 'payload', tag: %w(foo bar)) }

        it "queries with -tag" do
          expect_serf('query', '-format', 'json', '-tag=foo', '-tag=bar', 'test', 'payload', message: json)
          query
        end
      end
    end

    include_examples "failure cases"

    context "when length exceeds limit" do
      it "raises error" do
        expect_serf('query', '-format', 'json', 'test', 'payload',
          success: false,
          message: 'Error sending event: query exceeds limit of 1024 bytes')

        expect {
          subject
        }.to raise_error(
          Villein::Client::LengthExceedsLimitError,
          'Error sending event: query exceeds limit of 1024 bytes')
      end
    end
  end

  describe "#join" do
    subject { client.join('y.y.y.y:nnnn') }

    it "attempts to join another node" do
      expect_serf('join', 'y.y.y.y:nnnn')

      subject
    end

    context "with replay=true" do
      subject { client.join('y.y.y.y:nnnn', replay: true) }

      it "attempts to join another node with replaying" do
        expect_serf('join', '-replay', 'y.y.y.y:nnnn')

        subject
      end
    end

    include_examples "failure cases"
  end

  describe "#leave" do
    subject { client.leave }

    it "attempts to leave from cluster" do
      expect_serf('leave')

      subject
    end

    include_examples "failure cases"
  end

  describe "#force_leave" do
    subject { client.force_leave('the-node') }

    it "attempts to remove member forcely" do
      expect_serf('force-leave', 'the-node')

      subject
    end

    include_examples "failure cases"
  end

  describe "#members" do
    let(:json) { (<<-EOJ).gsub(/\n|\s+/,'') }
    {"members":[{"name":"the-node","addr":"a.a.a.a:mmmm","port": 7948,
    "tags":{"key":"val"},"status":"alive","protocol":{"max":4,"min":2,"version":4}}]}
    EOJ

    subject(:members) { client.members }

    it "returns member list" do
      expect_serf('members', '-format', 'json', message: json)

      expect(members).to be_a_kind_of(Array)
      expect(members[0]["name"]).to eq "the-node"
    end

    context "with status filter" do
      it "returns member list" do
        expect_serf('members', '-format', 'json', '-status', 'alive', message: json)

        client.members(status: :alive)
      end
    end

    context "with name filter" do
      it "returns member list" do
        expect_serf('members', '-format', 'json', '-name', 'node', message: json)

        client.members(name: 'node')
      end
    end

    context "with tag filter" do
      it "returns member list" do
        expect_serf('members', *%w(-format json -tag a=1 -tag b=2), message: json)

        client.members(tags: {a: '1', b: '2'})
      end
    end

    include_examples "failure cases"
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
    subject { client.set_tag('newkey', 'newval') }

    it "sets tag" do
      expect_serf('tags', '-set', 'newkey=newval')

      subject
    end

    include_examples "failure cases"

    context "when length exceeds limit" do
      it "raises error" do
        expect_serf('tags', '-set', 'newkey=newval',
          success: false,
          message: 'Error setting tags: Encoded length of tags exceeds limit of 512 bytes')

        expect {
          client.set_tag('newkey', 'newval')
        }.to raise_error(
          Villein::Client::LengthExceedsLimitError,
          'Error setting tags: Encoded length of tags exceeds limit of 512 bytes')
      end
    end
  end

  describe "#delete_tag" do
    subject { client.delete_tag('newkey') }

    it "deletes tag" do
      expect_serf('tags', '-delete', 'newkey')

      subject
    end

    include_examples "failure cases"
  end

  describe "#get_tags" do
    subject(:tags) { client.get_tags }

    it "retrieves using #member(name: )" do
      json = (<<-EOJ).gsub(/\n|\s+/,'')
        {"members":[{"name":"the-node","addr":"a.a.a.a:mmmm","port": 7948,
        "tags":{"key":"val"},"status":"alive","protocol":{"max":4,"min":2,"version":4}}]}
      EOJ

      expect_serf('members', *%w(-format json -name the-node), message: json)

      expect(tags).to be_a_kind_of(Hash)
      expect(tags['key']).to eq 'val'
    end

    context "without name" do
      let(:name) { nil }

      it "raises error" do
        expect { tags }.to raise_error
      end
    end

    include_examples "failure cases"
  end
end

