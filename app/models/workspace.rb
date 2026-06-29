# frozen_string_literal: true

# The tenant root — an agency. Everything domain-level hangs off a workspace.
class Workspace < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :clients, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :meetings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :social_accounts, dependent: :destroy
  has_many :creatives, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :generations, dependent: :destroy
  has_one  :setting, dependent: :destroy
  has_one  :subscription, dependent: :destroy

  has_one_attached :logo
  has_one_attached :default_creator_avatar

  SLUG_FORMAT = /\A[a-z0-9][a-z0-9-]{0,61}[a-z0-9]?\z/

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }

  def seat_count = memberships.count
  def plan = subscription&.plan&.to_sym || :solo
  def trialing? = subscription&.trialing? || false
  def billing_active? = subscription&.access_granted? || false

  def owner_membership = memberships.find_by(role: :owner)
  def owner = owner_membership&.user

  def seat_limit = subscription&.seat_limit || Subscription::SEAT_LIMITS["solo"]
  def within_seat_limit? = seat_count < seat_limit
end
