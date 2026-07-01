# frozen_string_literal: true

class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    # Audit trail for platform-staff override/destructive actions (impersonation,
    # godfathered toggles, manual credit grants, comps). LGPD accountability.
    create_table :admin_audit_logs do |t|
      t.references :staff_user, null: true, foreign_key: { to_table: :users }
      t.string  :action, null: false
      t.string  :target_type
      t.bigint  :target_id
      t.jsonb   :metadata, null: false, default: {}
      t.string  :ip_address
      t.timestamps
    end

    add_index :admin_audit_logs, %i[target_type target_id]
    add_index :admin_audit_logs, %i[action created_at]
  end
end
