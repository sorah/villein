require 'spec_helper'
require 'villein/event'

describe Villein::Event do
  it "holds event variables" do
    event = Villein::Event.new(
      type: 'type',
      self_name: 'self_name',
      self_tags: 'self_tags',
      user_event: 'user_event',
      query_name: 'query_name',
      user_ltime: 'user_ltime',
      query_ltime: 'query_ltime',
      payload: 'payload',
    )

    expect(event.type).to eq 'type'
    expect(event.self_name).to eq 'self_name'
    expect(event.self_tags).to eq 'self_tags'
    expect(event.user_event).to eq 'user_event'
    expect(event.query_name).to eq 'query_name'
    expect(event.user_ltime).to eq 'user_ltime'
    expect(event.query_ltime).to eq 'query_ltime'
    expect(event.payload).to eq 'payload'
  end

  describe "#ltime" do
    it "returns user_ltime or query_ltime" do
      expect(described_class.new(user_ltime: nil, query_ltime: '2').ltime).to eq '2'
      expect(described_class.new(user_ltime: '1', query_ltime: nil).ltime).to eq '1'
      expect(described_class.new(user_ltime: '1', query_ltime: '2').ltime).to eq '1'
    end
  end

  describe "#members" do
    context "when event is member-*" do
      let(:payload) {  "the-node\tX.X.X.X\t\tkey=val,a=b\nanother-node\tY.Y.Y.Y\t\tkey=val,a=b\n" }
      subject(:event) { Villein::Event.new(type: 'member-join', payload: payload) }

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
