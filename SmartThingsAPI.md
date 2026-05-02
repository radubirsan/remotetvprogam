# Integrating Samsung SmartThings API via OAuth Web View

This document outlines the step-by-step process for authenticating users and accessing the SmartThings API within an iOS application. It uses the standard OAuth 2.0 Authorization Code flow.

## Phase 1: Setup and Registration (SmartThings Workspace)

Before writing any code, you must register your application with Samsung to get your API credentials.

1. **Create a Developer Account:** Navigate to the [SmartThings Developer Workspace](https://smartthings.developer.samsung.com/workspace/) and log in.
2. **Create a New Project:** Select "Automation for the SmartThings App" or a generic API Integration.
3. **Gather Credentials:** Once created, navigate to the app settings and copy your `Client ID` and `Client Secret`. **Keep the secret secure.**
4. **Configure Redirect URIs:** Add a custom URL scheme that your iOS app will listen to (e.g., `yourappname://oauth-callback`). SmartThings will redirect the web view to this URL after the user logs in.
5. **Define Scopes:** Select the permissions your app needs. For a remote control, you will likely need scopes like `r:devices:*` (read devices) and `x:devices:*` (execute commands on devices).

---

## Phase 2: The Authentication Web View (iOS App)

Apple strongly recommends using `ASWebAuthenticationSession` over a standard `WKWebView` for OAuth flows. It handles cookie sharing securely and provides a native, trusted UI.

1. **Import Authentication Services:** Add `import AuthenticationServices` to your Swift file.
2. **Construct the Authorization URL:** Build the URL to direct the user to Samsung's login page.
   * **Base URL:** `https://api.smartthings.com/oauth/authorize`
   * **Query Parameters:**
     * `client_id`: Your Client ID.
     * `response_type`: Set this to `code`.
     * `redirect_uri`: Your custom URL scheme (e.g., `yourappname://oauth-callback`).
     * `scope`: Space-separated list of scopes (e.g., `r:devices:* x:devices:*`).
3. **Present the Session:** Initialize `ASWebAuthenticationSession` with the URL and your callback scheme. Call `.start()` to present the login modal. The user will log into their Samsung account and tap "Authorize".

---

## Phase 3: Handling the Callback

Once the user approves the connection, Samsung will redirect the web view back to your app using the `redirect_uri`.

1. **Intercept the Redirect:** `ASWebAuthenticationSession` handles this automatically via its completion handler.
2. **Extract the Authorization Code:** The returned URL will look like `yourappname://oauth-callback?code=abc123xyz`. Parse this URL to extract the `code` parameter. This code is temporary and usually expires in a few minutes.

---

## Phase 4: Token Exchange

You cannot use the Authorization Code to make API calls. You must exchange it for an Access Token.

1. **Make a POST Request:** Create a background network request (using `URLSession`) to the SmartThings token endpoint: `https://api.smartthings.com/oauth/token`.
2. **Set the Payload (Form-URL-Encoded):**
   * `grant_type`: `authorization_code`
   * `client_id`: Your Client ID
   * `client_secret`: Your Client Secret
   * `code`: The authorization code you just extracted
   * `redirect_uri`: The exact same redirect URI used in Phase 2.
3. **Receive the Tokens:** Parse the JSON response. You will receive an `access_token` (used for API calls) and a `refresh_token` (used to get a new access token when the current one expires).

---

## Phase 5: Storage and Usage

1. **Secure Storage:** **Never** store tokens in `UserDefaults`. Save both the `access_token` and `refresh_token` securely in the iOS **Keychain**.
2. **Make Authenticated API Calls:** To control the TV, make standard HTTP requests to the SmartThings REST API (e.g., `https://api.smartthings.com/v1/devices/{deviceId}/commands`).
   * Attach your token in the HTTP Headers: `Authorization: Bearer YOUR_ACCESS_TOKEN`.
3. **Handle Token Expiration:** Access tokens expire (usually after 24 hours). When an API call fails with a `401 Unauthorized` error, use your `refresh_token` to hit the token endpoint (`grant_type=refresh_token`) to silently get a new access token without making the user log in again.
