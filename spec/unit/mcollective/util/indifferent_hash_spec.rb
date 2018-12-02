require "spec_helper"
require "mcollective/util/indifferent_hash"

module MCollective
  module Util
    describe IndifferentHash do
      describe "#[]" do
        it "should correctly grant indifferent access" do
          h = IndifferentHash["x" => "y"]
          expect(h[:x]).to eq("y")
          expect(h["x"]).to eq("y")

          h = IndifferentHash[:x => "y"]
          expect(h[:x]).to eq("y")
          expect(h["x"]).to be_nil
        end
      end
    end
  end
end
