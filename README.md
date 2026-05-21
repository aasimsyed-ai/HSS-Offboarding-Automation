# HSS Offboarding Task Helper

This folder captures the daily offboarding workflow for:

> Rename AD Account to Add Pending Termination Date

The current bot is intentionally human-confirmed. It calculates the exact rename value, prints the checklist to follow in ServiceNow and Active Directory, and saves a local run log, but it does not directly modify AD.

## Quick Start

Open PowerShell in this folder and run:

```powershell
.\tools\Start-HssOffboardingTask.ps1
```

The bot will ask for:

- SCTASK number
- RITM number
- Departed employee full name
- AD username from the AD account section
- Departure Date
- Whether **Email forwarding** is checked
- Whether **Email Access** is checked
- Whether the AD account is already disabled

It will then print:

- The exact AD rename value
- The AD steps to perform through Omnisa Horizon / VDI
- The exact ServiceNow closure comments
- The **Closed Complete** status reminder

Local run logs are saved to `logs/`. The `logs/` folder is ignored by Git so ticket/user data does not get uploaded.

## Daily Flow

1. Open ServiceNow in Edge.
2. Go to Favorites, then open **Offboarding task**.
3. Look for a task with short description:
   `Disable account and rename to Full Name-Pending Termination for`
4. If no matching task exists, there is no action for this workflow.
5. If a matching SCTASK exists, open it and copy the **Request Number** that starts with `RITM`.
6. Paste/open that RITM in another ServiceNow tab for easier reference.
7. From the RITM, capture:
   - Departed employee full name
   - AD username
   - Request number / RITM number
   - **Departure Date**
   - Whether **Email forwarding** or **Email Access** is checked
8. Find the AD username in the **AD account** section.
9. Run the helper script to calculate the AD rename value.
10. In Active Directory through Omnisa Horizon / VDI:
   - Login to Active Directory.
   - Right click `NA.IKO`.
   - Choose **Find User**.
   - Type the user name.
   - From search results, right click the user.
   - Click **Rename**.
   - Enter the generated rename value.
   - Click **OK**.
   - Do not change any other fields.
11. Reset the user account password:
   - Right click the user account.
   - Click **Reset Password**.
   - Enter a password of your own choice.
12. Update the SCTASK:
   - If the account was already disabled, add:
     `As checked, the account is already disabled.`
   - Add:
     `Performed password reset.`
   - Add:
     `Renamed the user in AD.`
   - Change the status to **Closed Complete**.
13. Return to the RITM and continue with any newly created tasks.

## Pending Termination Date Rules

- If the user requires email forwarding or email access, use termination date plus 3 months.
- If the user does not require any access, use termination date plus 1 month.

Example:

```powershell
.\tools\New-HssOffboardingChecklist.ps1 `
  -FullName "Jane Doe" `
  -SamAccountName "jdoe" `
  -RitmNumber "RITM1234567" `
  -TerminationDate "2026-01-01" `
  -EmailForwardingOrAccessRequired
```

Output rename value:

```text
Jane Doe Pending Termination 1 April 2026 RITM1234567
```

## Safety Notes

- Do not rename accounts unless the ServiceNow task matches the expected short description.
- Do not change any AD fields other than the account rename.
- Confirm the calculated date before saving in AD.
- Keep a copy of the ServiceNow task number/RITM in your work notes.
- Do not use local PowerShell AD cmdlets for this workflow. AD actions should be completed through the approved VDI GUI.
