# HSS Offboarding Decision Matrix

Use this before making any AD change.

## ServiceNow Task Detection

| Condition | Action |
| --- | --- |
| No task exists in **Offboarding task** favorites view | Stop. No work for this process. |
| Task exists but short description does not contain `Disable account and rename to Full Name-Pending Termination for` | Stop. This helper does not apply. |
| One matching task exists | Continue with field capture and AD lookup. |
| Multiple matching tasks exist | Process one task at a time. Do not combine users or RITMs. |

## ServiceNow RITM Reference

| Step | Action |
| --- | --- |
| Open matching SCTASK | Copy the **Request Number** beginning with `RITM`. |
| Open another ServiceNow tab | Paste/open the RITM for easier reference. |
| In the RITM | Read **Departure Date**. |
| In the RITM | Check whether **Email forwarding** or **Email Access** is selected. |
| In the RITM | Find AD username in the **AD account** section. |

## Required Ticket Inputs

| Input | Required? | If Missing |
| --- | --- | --- |
| Full name | Yes | Stop and verify ServiceNow ticket details. |
| AD username / account ID | Yes | Stop and verify ServiceNow ticket details. |
| RITM number | Yes | Stop and verify ServiceNow ticket details. |
| Departure Date | Yes | Stop and verify ServiceNow ticket details. |
| Email forwarding or email access requirement | Yes | Stop and verify whether pending date should be plus 3 months or plus 1 month. |

## Pending Termination Date

| Condition | Date Rule |
| --- | --- |
| User requires email forwarding | Termination date plus 3 months |
| User requires email access | Termination date plus 3 months |
| User requires neither email forwarding nor email access | Termination date plus 1 month |
| Ticket is unclear about access | Stop and clarify before renaming |

## AD Search Results

| Condition | Action |
| --- | --- |
| No AD user found | Stop and verify username/ticket. |
| Exactly one AD user found | Continue. |
| Multiple users found | Stop and identify the correct account before renaming. |
| User already contains `Pending Termination` in the name | Stop and verify whether the task was already completed. |

## AD Rename Rule

Use this exact format:

```text
[Departed Employee Full Name] Pending Termination [Agreed Date] [RITM Number]
```

Do not change any other AD fields.

## Password Reset

After the rename:

1. Right click the user account.
2. Click **Reset Password**.
3. Enter a password of your own choice.

## ServiceNow Closure Notes

After AD rename and password reset, update the SCTASK.

If the AD account was already disabled, add:

```text
As checked, the account is already disabled.
```

Always add:

```text
Performed password reset.
Renamed the user in AD.
```

Then change the SCTASK status to **Closed Complete**.

After closure, return to the RITM because more tasks may be created under the same request.

## Items To Confirm Before Full UI Automation

Before building a click-through automation for Edge, ServiceNow, Omnisa Horizon, and AD, confirm:

- Whether the ServiceNow task table can be exported or accessed through API.
- Exact field labels and stable UI positions for full name, username, RITM, Departure Date, and email access/forwarding requirement.
- AD changes must be completed through the VDI GUI for this workflow, not local PowerShell AD cmdlets.
- Whether password value rules are fixed or manually chosen each time.
- Whether completed ServiceNow tasks require any fields beyond closure notes and **Closed Complete** status.
