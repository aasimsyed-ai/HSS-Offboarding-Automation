# HSS Offboarding Task Helper

This folder captures the daily offboarding workflow for:

> Rename AD Account to Add Pending Termination Date

The current bot is intentionally human-confirmed. It calculates the exact rename value, prints the checklist to follow in ServiceNow and Active Directory, and saves a local run log, but it does not directly modify AD.

## Quick Start

For real mouse/keyboard automation, use the Python RPA bot.

First-time setup:

```cmd
cd "C:\Users\aasim.rauf\Documents\New project\hss-offboarding"
setup-rpa.cmd
calibrate-rpa.cmd
```

Daily run:

```cmd
cd "C:\Users\aasim.rauf\Documents\New project\hss-offboarding"
run-rpa.cmd
```

The RPA bot controls the laptop mouse and keyboard. It can open/focus Edge and Horizon, read/copy calibrated ServiceNow fields, paste into AD, reset the password, and close the SCTASK.

Emergency stop: move the mouse to the upper-left corner of the screen.

The older PowerShell helper is still available:

```powershell
.\tools\Start-HssOffboardingTask.ps1
```

The helper will ask for:

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
- The standard reset password it will paste
- The **Closed Complete** status it will apply

At the end, it can also launch/focus Horizon and assist with AD GUI typing:

- Paste the AD username into the AD search box
- Paste the exact rename value into the Rename field
- Confirm the rename after you review it
- Paste the standard password into the Reset Password dialog
- Submit the password reset after you review it

This is attended automation. The bot pauses before each AD write action so you can confirm the right user and dialog are active.

It can also focus ServiceNow in Edge and assist with closure:

- Paste the correct Work notes
- Set the SCTASK status to **Closed Complete**
- Send `Ctrl+S` after you review the form

If your ServiceNow form requires clicking an **Update** button instead of `Ctrl+S`, click **Update** manually when prompted.

Local run logs are saved to `logs/`. The `logs/` folder is ignored by Git so ticket/user data does not get uploaded.

## Test / Reference Modes

To test the Python RPA calculation only:

```cmd
run-rpa.cmd --manual --dry-run
```

To run the Python RPA but skip AD:

```cmd
run-rpa.cmd --skip-ad
```

To run the Python RPA but skip ServiceNow closure:

```cmd
run-rpa.cmd --skip-servicenow
```

To show the old checklist while running automation:

```powershell
.\tools\Start-HssOffboardingTask.ps1 -ShowChecklist
```

To test calculation and logging without touching Horizon or ServiceNow:

```powershell
.\tools\Start-HssOffboardingTask.ps1 -SkipVdi -SkipServiceNow
```

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
   - Enter the standard reset password for this workflow.
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
- In AD rename text, use `PendingTermination` without a space.
- In AD rename text, use date format `DDMMMYY`, for example `01APR26`.

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
Jane Doe PendingTermination 01APR26 RITM1234567
```

## Safety Notes

- Do not rename accounts unless the ServiceNow task matches the expected short description.
- Do not change any AD fields other than the account rename.
- Confirm the calculated date before saving in AD.
- Keep a copy of the ServiceNow task number/RITM in your work notes.
- Do not use local PowerShell AD cmdlets for this workflow. AD actions should be completed through the approved VDI GUI.
- When using VDI automation, confirm the correct AD user is selected before allowing the bot to submit rename or password reset.
