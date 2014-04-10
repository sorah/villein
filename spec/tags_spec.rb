require 'spec_helper'
require 'villein/tags'

describe Villein::Tags do
  let(:parent) { double('parent', get_tags: {'a' => '1'}) }
  subject(:tags) { described_class.new(parent) }

  describe "#[]" do
    it "returns value for key in Symbol" do
      expect(tags[:a]).to eq '1'
    end

    it "returns value for key in String" do
      expect(tags['a']).to eq '1'
    end
  end

  describe "#[]=" do
    it "sets value for key in Symbol, using parent#set_tag" do
      expect(parent).to receive(:set_tag).with('b', "1").and_return('1')

      tags['b'] = 1

      expect(tags['b']).to eq '1'
    end

    it "sets value for key in String, using parent#set_tag" do
      expect(parent).to receive(:set_tag).with('b', "1").and_return('1')

      tags[:b] = 1

      expect(tags[:b]).to eq '1'
    end

    context "with nil" do
      it "deletes key" do
        expect(tags).to receive(:delete).with('b')
        tags[:b] = nil
      end
    end
  end

  describe "#delete" do
    it "deletes key, using parent#delete_tag" do
      expect(parent).to receive(:delete_tag).with('a')
      tags.delete :a
      expect(tags[:a]).to be_nil
    end
  end

  describe "#to_h" do
    it "returns hash" do
      expect(tags.to_h).to eq('a' => '1')
    end
  end

  describe "#reload" do
    it "retrieves latest tag using parent#get_tags" do
      tags # init
      allow(parent).to receive(:get_tags).and_return('new' => 'tag')

      expect {
        tags.reload
      }.to change { tags['new'] } \
       .from(nil).to('tag')
    end
  end
end
