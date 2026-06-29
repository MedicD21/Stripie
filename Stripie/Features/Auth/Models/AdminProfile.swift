import Foundation

/// The authenticated admin's profile, as returned by the Good Kitchen
/// `admin-portal-auth` function. A signed-in user is always at least an admin;
/// `isSuperAdmin` distinguishes super-admins (currently informational only).
struct AdminProfile: Codable, Equatable, Sendable {
    var email: String
    var displayName: String?
    var name: String?
    var firstName: String?
    var lastName: String?
    var profileImageUrl: String?
    var isSuperAdmin: Bool

    init(
        email: String,
        displayName: String? = nil,
        name: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        profileImageUrl: String? = nil,
        isSuperAdmin: Bool = false
    ) {
        self.email = email
        self.displayName = displayName
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.profileImageUrl = profileImageUrl
        self.isSuperAdmin = isSuperAdmin
    }

    // The server omits several fields depending on the action (e.g. `verify_code`
    // does not include `is_super_admin`), so decode everything defensively.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = (try c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        profileImageUrl = try c.decodeIfPresent(String.self, forKey: .profileImageUrl)
        isSuperAdmin = (try c.decodeIfPresent(Bool.self, forKey: .isSuperAdmin)) ?? false
    }

    /// Best available human-friendly name, falling back to the email.
    var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let name, !name.isEmpty { return name }
        return email
    }

    var roleLabel: String { isSuperAdmin ? "Super Admin" : "Admin" }
}
