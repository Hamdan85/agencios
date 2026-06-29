// Membership-role capability helpers, mirroring the backend Membership predicates
// (Membership#can_manage? / #can_admin?). `role` is the string from `me.membership.role`.
const MANAGE_ROLES = ['owner', 'admin', 'manager']
const ADMIN_ROLES = ['owner', 'admin']

export const canManage = (role) => MANAGE_ROLES.includes(role)
export const canAdmin = (role) => ADMIN_ROLES.includes(role)
