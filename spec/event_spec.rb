require 'spec_helper'
require 'villein/event'

describe Villein::Event do
  it "holds event variables" do
    event = Villein::Event.new(
      'SERF_EVENT'       => 'type',
      'SERF_SELF_NAME'   => 'self_name',
      'SERF_TAG_key'     => 'val',
      'SERF_TAG_key2'    => 'val2',
      'SERF_USER_EVENT'  => 'user_event',
      'SERF_QUERY_NAME'  => 'query_name',
      'SERF_USER_LTIME'  => 'user_ltime',
      'SERF_QUERY_LTIME' => 'query_ltime',
      payload: 'payload',
    )

    expect(event.type).to eq 'type'
    expect(event.self_name).to eq 'self_name'
    expect(event.self_tags).to eq('key' => 'val', 'key2' => 'val2')
    expect(event.user_event).to eq 'user_event'
    expect(event.query_name).to eq 'query_name'
    expect(event.user_ltime).to eq 'user_ltime'
    expect(event.query_ltime).to eq 'query_ltime'
    expect(event.payload).to eq 'payload'
  end

  describe "#ltime" do
    it "returns user_ltime or query_ltime" do
      expect(described_class.new('SERF_USER_LTIME' => nil, 'SERF_QUERY_LTIME' => '2').ltime).to eq '2'
      expect(described_class.new('SERF_USER_LTIME' => '1', 'SERF_QUERY_LTIME' => nil).ltime).to eq '1'
      expect(described_class.new('SERF_USER_LTIME' => '1', 'SERF_QUERY_LTIME' => '2').ltime).to eq '1'
    end
  end

  describe "#members" do
    context "when event is member-*" do
      let(:payload) {  "the-node\tX.X.X.X\t\tkey=val,a=b\nanother-node\tY.Y.Y.Y\t\tkey=val,a=b\n" }
      subject(:event) { Villein::Event.new('SERF_EVENT' => 'member-join', payload: payload) }

      it "parses member list" do
        expect(event.members).to be_a_kind_of(Array)
        expect(event.members.size).to eq 2
        expect(event.members[0]).to eq(name: 'the-node', address: 'X.X.X.X', tags: {'key' => 'val', 'a' => 'b'})
        expect(event.members[1]).to eq(name: 'another-node', address: 'Y.Y.Y.Y', tags: {'key' => 'val', 'a' => 'b'})
      end

      context "with confused tags" do
        let(:payload) { "the-node\tX.X.X.X\t\taa=b=,,c=d,e=f,g,h,i=j\n" }

        it "parses greedily" do
          expect(event.members[0][:tags]).to eq("aa"=>"b=,", "c"=>"d", "e"=>"f,g,h", "i"=>"j")
        end
      end
    end
  end
end
