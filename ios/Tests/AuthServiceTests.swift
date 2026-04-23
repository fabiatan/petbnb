import XCTest
@testable import PetBnB

final class AuthServiceTests: XCTestCase {
    func test_auth_sign_up_input_holds_values() {
        let input = AuthSignUpInput(email: "a@b.co", password: "12345678", displayName: "Test")
        XCTAssertEqual(input.email, "a@b.co")
        XCTAssertEqual(input.password.count, 8)
        XCTAssertEqual(input.displayName, "Test")
    }

    func test_auth_service_error_has_readable_description() {
        let e = AuthServiceError.signInFailed("bad credentials")
        XCTAssertNotNil(e.errorDescription)
        XCTAssertTrue(e.errorDescription!.contains("Sign in failed"))
    }
}
