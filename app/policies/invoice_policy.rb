# frozen_string_literal: true

# Managers+ manage client invoices; members read; guests may only read.
class InvoicePolicy < ApplicationPolicy
  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?
  def cancel?  = manager?
end
