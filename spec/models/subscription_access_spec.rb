# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription, type: :model do
  def sub(attrs)
    ws = Workspace.create!(name: "W", slug: "w-#{SecureRandom.hex(6)}")
    Subscription.create!({ workspace: ws, plan: :solo, seats: 1 }.merge(attrs))
  end

  describe "#access_granted? (no free tier, card-required trial)" do
    it "grants access when active" do
      expect(sub(status: "active").access_granted?).to be(true)
    end

    it "grants access when past_due (dunning window)" do
      expect(sub(status: "past_due").access_granted?).to be(true)
    end

    it "denies a trial WITHOUT a card on file" do
      expect(sub(status: "trialing", card_on_file: false, trial_ends_at: 3.days.from_now).access_granted?).to be(false)
    end

    it "grants a trial WITH a card on file and an open window" do
      expect(sub(status: "trialing", card_on_file: true, trial_ends_at: 3.days.from_now).access_granted?).to be(true)
    end

    it "denies a trial WITH a card but an expired window" do
      expect(sub(status: "trialing", card_on_file: true, trial_ends_at: 1.day.ago).access_granted?).to be(false)
    end

    it "denies incomplete (awaiting payment) and canceled" do
      expect(sub(status: "incomplete").access_granted?).to be(false)
      expect(sub(status: "canceled").access_granted?).to be(false)
    end
  end
end
