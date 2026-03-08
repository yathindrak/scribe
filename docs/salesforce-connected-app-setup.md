# Salesforce Connected App Setup

## Context

Since September 2025, Salesforce requires connected apps to be **installed** in each org.
External Client Apps (the newer type) are org-local and don't support multi-tenant OAuth.
Use a **Classic Connected App** deployed via Salesforce CLI instead.

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) installed (`sf --version`)
- Admin access to your Salesforce org

## Steps

### 1. Login to your Salesforce org

```bash
sf org login web
```

### 2. Create the metadata directory

```bash
mkdir -p /tmp/sf-connected-app/force-app/main/default/connectedApps
```

### 3. Create the Connected App metadata file

Create `/tmp/sf-connected-app/force-app/main/default/connectedApps/ScribeProd.connectedApp-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ConnectedApp xmlns="http://soap.sforce.com/2006/04/metadata">
    <contactEmail>your-email@example.com</contactEmail>
    <label>Scribe Prod</label>
    <oauthConfig>
        <callbackUrl>https://scribe-yathindra.fly.dev/auth/salesforce/callback</callbackUrl>
        <isAdminApproved>false</isAdminApproved>
        <isPkceRequired>true</isPkceRequired>
        <scopes>Api</scopes>
        <scopes>RefreshToken</scopes>
        <scopes>OfflineAccess</scopes>
    </oauthConfig>
</ConnectedApp>
```

### 4. Create the sfdx-project.json

Create `/tmp/sf-connected-app/sfdx-project.json`:

```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true
    }
  ],
  "name": "sf-connected-app",
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "59.0"
}
```

### 5. Deploy to Salesforce

```bash
cd /tmp/sf-connected-app && sf project deploy start --source-dir force-app --target-org <your-username>
```

### 6. Retrieve to get the generated Client ID

```bash
sf project retrieve start --metadata "ConnectedApp:ScribeProd" --target-org <your-username> && cat force-app/main/default/connectedApps/ScribeProd.connectedApp-meta.xml
```

The `consumerKey` in the retrieved file is your **Client ID**.

### 7. Get the Client Secret

The secret is not included in metadata. Retrieve it from the Salesforce UI:

1. Go to **Setup → App Manager**
2. Find **Scribe Prod** → click **View**
3. Click **Manage Consumer Details**
4. Copy the **Consumer Secret**

### 8. Update fly.dev secrets

```bash
fly secrets set \
  SALESFORCE_CLIENT_ID="<consumer-key-from-step-6>" \
  SALESFORCE_CLIENT_SECRET="<consumer-secret-from-step-7>" \
  -a scribe-yathindra
```

## Notes

- The Classic Connected App works cross-org — any Salesforce user can authorize via `login.salesforce.com`
- PKCE is required (`isPkceRequired=true`) as the Ueberauth Salesforce strategy uses it
