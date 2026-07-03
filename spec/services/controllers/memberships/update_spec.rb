# frozen_string_literal: true

require 'rails_helper'

# Role changes: the owner role (billing + workspace deletion) is only granted /
# revoked by an owner, and the workspace can never be left ownerless.
RSpec.describe Controllers::Memberships::Update do
  let(:owner) { User.create!(email: 'own@agencios.app', password: 'secret123', name: 'Owner') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio Co') }
  let(:owner_membership) { workspace.memberships.find_by(user: owner) }
  let(:member) do
    u = User.create!(email: 'mem@agencios.app', password: 'secret123', name: 'Mem')
    workspace.memberships.create!(user: u, role: :manager)
  end

  before { Current.workspace = workspace }
  after { Current.reset }

  def as(membership) = Current.membership = membership

  def update_role(target, role)
    described_class.call(params: ActionController::Parameters.new(id: target.id, role: role))
  end

  it 'keeps the workspace single-owner (model refuses a second owner even for the owner)' do
    as(owner_membership)
    expect { update_role(member, 'owner') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'forbids a manager from granting the owner role' do
    as(member) # manager
    other = workspace.memberships.create!(
      user: User.create!(email: 'x@agencios.app', password: 'secret123', name: 'X'), role: :member
    )
    expect { update_role(other, 'owner') }.to raise_error(Operations::Errors::Forbidden)
  end

  it 'forbids a manager from demoting an owner' do
    as(member)
    expect { update_role(owner_membership, 'member') }.to raise_error(Operations::Errors::Forbidden)
  end

  it 'never leaves the workspace without an owner (sole owner cannot demote themselves)' do
    as(owner_membership)
    expect { update_role(owner_membership, 'member') }
      .to raise_error(Operations::Errors::Invalid, /ao menos um owner/)
  end

  it 'still allows normal role changes below owner' do
    as(owner_membership)
    update_role(member, 'member')
    expect(member.reload.role).to eq('member')
  end
end
