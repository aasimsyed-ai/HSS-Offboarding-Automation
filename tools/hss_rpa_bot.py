import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "rpa_config.json"
CONFIG_EXAMPLE_PATH = ROOT / "rpa_config.example.json"
DEFAULT_PASSWORD = "Qwerty@12345"
SHORT_DESCRIPTION = "Disable account and rename to Full Name-Pending Termination for"


def require_rpa_modules():
    missing = []
    for module in ("pyautogui", "pyperclip", "PIL"):
        try:
            __import__(module)
        except ImportError:
            missing.append(module)

    if missing:
        print("Missing Python RPA modules:", ", ".join(missing))
        print("Run this first:")
        print(f'  "{ROOT / "setup-rpa.cmd"}"')
        sys.exit(1)

    import pyautogui
    import pyperclip

    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.15
    return pyautogui, pyperclip


def load_config():
    if not CONFIG_PATH.exists():
        shutil.copyfile(CONFIG_EXAMPLE_PATH, CONFIG_PATH)
        print(f"Created {CONFIG_PATH}")
        print("Run calibration before using full automation:")
        print(f'  "{ROOT / "calibrate-rpa.cmd"}"')
        sys.exit(1)

    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_config(config):
    with CONFIG_PATH.open("w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
        f.write("\n")


def pause(config, name):
    time.sleep(float(config.get("timing", {}).get(name, 0.5)))


def set_clipboard(pyperclip, text):
    pyperclip.copy(text)
    time.sleep(0.15)


def hotkey(pyautogui, *keys):
    pyautogui.hotkey(*keys)
    time.sleep(0.25)


def click_coord(pyautogui, config, path):
    section = config
    for key in path:
        section = section[key]
    x, y = section
    if int(x) == 0 and int(y) == 0:
        raise RuntimeError(f"Coordinate not calibrated: {'.'.join(path)}")
    pyautogui.click(int(x), int(y))


def coord_is_set(config, path):
    section = config
    for key in path:
        section = section[key]
    x, y = section
    return int(x) != 0 or int(y) != 0


def paste_text(pyautogui, pyperclip, text):
    set_clipboard(pyperclip, text)
    hotkey(pyautogui, "ctrl", "v")


def prompt_required(label, pattern=None):
    while True:
        value = input(f"{label}: ").strip()
        if value and (not pattern or re.match(pattern, value, re.IGNORECASE)):
            return value
        print("Invalid value. Try again.")


def prompt_yes_no(label):
    while True:
        value = input(f"{label} (Y/N): ").strip().upper()
        if value in ("Y", "YES"):
            return True
        if value in ("N", "NO"):
            return False
        print("Enter Y or N.")


def parse_date(value):
    for fmt in ("%Y-%m-%d", "%d %B %Y", "%d-%m-%Y", "%d/%m/%Y", "%m/%d/%Y", "%d-%b-%Y", "%d-%b-%y", "%d %b %Y", "%d %b %y"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    raise ValueError("Use date like 2026-01-31 or 31 January 2026.")


def add_months(dt, months):
    month = dt.month - 1 + months
    year = dt.year + month // 12
    month = month % 12 + 1
    month_lengths = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    day = min(dt.day, month_lengths[month - 1])
    return dt.replace(year=year, month=month, day=day)


def ad_date(dt):
    return dt.strftime("%d%b%y").upper()


@dataclass
class TicketData:
    sctask: str
    ritm: str
    full_name: str
    ad_username: str
    departure_date: datetime
    email_forwarding: bool
    email_access: bool
    already_disabled: bool

    @property
    def pending_date(self):
        return add_months(self.departure_date, 3 if self.email_forwarding or self.email_access else 1)

    @property
    def rename_value(self):
        return f"{self.full_name} PendingTermination {ad_date(self.pending_date)} {self.ritm.upper()}"

    @property
    def work_notes(self):
        notes = []
        if self.already_disabled:
            notes.append("As checked, the account is already disabled.")
        notes.append("Performed password reset.")
        notes.append("Renamed the user in AD.")
        return "\n".join(notes)


def collect_manual_ticket_data():
    print("Enter ticket values. Later we can replace this with full ServiceNow screen scraping once calibrated.")
    sctask = prompt_required("SCTASK number", r"^SCTASK\d+$").upper()
    ritm = prompt_required("RITM number", r"^RITM\d+$").upper()
    full_name = prompt_required("Full name")
    ad_username = prompt_required("AD username")
    while True:
        try:
            departure_date = parse_date(prompt_required("Departure Date"))
            break
        except ValueError as exc:
            print(exc)
    email_forwarding = prompt_yes_no("Email forwarding checked")
    email_access = prompt_yes_no("Email Access checked")
    already_disabled = prompt_yes_no("Account already disabled")
    return TicketData(sctask, ritm, full_name, ad_username, departure_date, email_forwarding, email_access, already_disabled)


def copy_field_text(pyautogui, pyperclip, config, path, label):
    click_coord(pyautogui, config, path)
    pause(config, "short_pause")
    hotkey(pyautogui, "ctrl", "a")
    hotkey(pyautogui, "ctrl", "c")
    value = pyperclip.paste().strip()
    if not value:
        pyautogui.doubleClick()
        pause(config, "short_pause")
        hotkey(pyautogui, "ctrl", "c")
        value = pyperclip.paste().strip()
    if not value:
        raise RuntimeError(f"Could not copy {label}. Calibrate that field or use --manual.")
    print(f"Copied {label}: {value}")
    return value


def copy_checkbox_state(pyautogui, pyperclip, config, path, label):
    # Most ServiceNow checkboxes expose checked state poorly to clipboard.
    # The reliable RPA option is to hover/click near the box and ask once until image/OCR is added.
    if not coord_is_set(config, path):
        return prompt_yes_no(f"{label} checked")
    click_coord(pyautogui, config, path)
    pause(config, "short_pause")
    return prompt_yes_no(f"Bot focused {label}. Is it checked")


def collect_ticket_data_from_servicenow(pyautogui, pyperclip, config):
    print("Screen mode: opening matching SCTASK and reading calibrated ServiceNow fields.")
    open_offboarding_tasks(pyautogui, pyperclip, config)
    find_matching_sctask(pyautogui, pyperclip, config)

    sctask = prompt_required("Confirm opened SCTASK number", r"^SCTASK\d+$").upper()
    ritm = copy_field_text(pyautogui, pyperclip, config, ["servicenow", "coordinates", "request_number_field"], "RITM number")

    print("Opening RITM in a duplicated/new tab.")
    hotkey(pyautogui, "ctrl", "l")
    hotkey(pyautogui, "ctrl", "c")
    current_url = pyperclip.paste()
    hotkey(pyautogui, "ctrl", "l")
    paste_text(pyautogui, pyperclip, current_url)
    hotkey(pyautogui, "alt", "enter")
    pause(config, "medium_pause")

    search_hotkey = config.get("servicenow", {}).get("global_search_hotkey", [])
    if search_hotkey:
        hotkey(pyautogui, *search_hotkey)
        paste_text(pyautogui, pyperclip, ritm)
        pyautogui.press("enter")
        pause(config, "long_pause")
    else:
        print("No ServiceNow global search hotkey configured. Open the RITM tab manually, then press Enter.")
        input()

    full_name = copy_field_text(pyautogui, pyperclip, config, ["servicenow", "coordinates", "ritm_full_name_field"], "full name")
    ad_username = copy_field_text(pyautogui, pyperclip, config, ["servicenow", "coordinates", "ritm_ad_username_field"], "AD username")
    departure_raw = copy_field_text(pyautogui, pyperclip, config, ["servicenow", "coordinates", "ritm_departure_date_field"], "Departure Date")
    departure_date = parse_date(departure_raw)
    email_forwarding = copy_checkbox_state(pyautogui, pyperclip, config, ["servicenow", "coordinates", "ritm_email_forwarding_checkbox"], "Email forwarding")
    email_access = copy_checkbox_state(pyautogui, pyperclip, config, ["servicenow", "coordinates", "ritm_email_access_checkbox"], "Email Access")
    already_disabled = prompt_yes_no("Account already disabled in AD")

    return TicketData(sctask, ritm, full_name, ad_username, departure_date, email_forwarding, email_access, already_disabled)


def focus_edge(pyautogui, config):
    subprocess.Popen(["cmd", "/c", "start", "msedge"], shell=False)
    pause(config, "medium_pause")
    hotkey(pyautogui, "alt", "tab")
    pause(config, "short_pause")


def focus_horizon(pyautogui, config):
    horizon = r"C:\Program Files\Omnissa\Omnissa Horizon Client\horizon-client.exe"
    if os.path.exists(horizon):
        subprocess.Popen([horizon])
    pause(config, "long_pause")
    hotkey(pyautogui, "alt", "tab")
    pause(config, "short_pause")


def open_offboarding_tasks(pyautogui, pyperclip, config):
    url = config.get("servicenow", {}).get("offboarding_tasks_url", "")
    focus_edge(pyautogui, config)
    if url:
        hotkey(pyautogui, "ctrl", "l")
        paste_text(pyautogui, pyperclip, url)
        pyautogui.press("enter")
        pause(config, "long_pause")
    else:
        print("No offboarding_tasks_url is configured. The bot assumes the Offboarding task list is already open in Edge.")


def find_matching_sctask(pyautogui, pyperclip, config):
    hotkey(pyautogui, "ctrl", "f")
    paste_text(pyautogui, pyperclip, SHORT_DESCRIPTION)
    pyautogui.press("esc")
    pause(config, "short_pause")
    click_coord(pyautogui, config, ["servicenow", "coordinates", "first_matching_task_row"])
    pause(config, "long_pause")


def automate_ad(pyautogui, pyperclip, config, ticket):
    focus_horizon(pyautogui, config)
    print("Automating AD search, rename, and password reset.")
    print("Move mouse to upper-left corner any time to emergency stop.")

    click_coord(pyautogui, config, ["ad", "coordinates", "find_user_search_box"])
    hotkey(pyautogui, "ctrl", "a")
    paste_text(pyautogui, pyperclip, ticket.ad_username)
    click_coord(pyautogui, config, ["ad", "coordinates", "find_now_button"])
    pause(config, "long_pause")

    click_coord(pyautogui, config, ["ad", "coordinates", "first_search_result"])
    pyautogui.rightClick()
    pause(config, "short_pause")
    click_coord(pyautogui, config, ["ad", "coordinates", "rename_menu_item"])
    pause(config, "short_pause")
    hotkey(pyautogui, "ctrl", "a")
    paste_text(pyautogui, pyperclip, ticket.rename_value)
    pyautogui.press("enter")
    pause(config, "medium_pause")

    click_coord(pyautogui, config, ["ad", "coordinates", "find_user_search_box"])
    hotkey(pyautogui, "ctrl", "a")
    paste_text(pyautogui, pyperclip, ticket.ad_username)
    click_coord(pyautogui, config, ["ad", "coordinates", "find_now_button"])
    pause(config, "long_pause")
    click_coord(pyautogui, config, ["ad", "coordinates", "first_search_result"])
    pyautogui.rightClick()
    pause(config, "short_pause")
    click_coord(pyautogui, config, ["ad", "coordinates", "reset_password_menu_item"])
    pause(config, "medium_pause")
    click_coord(pyautogui, config, ["ad", "coordinates", "new_password_field"])
    paste_text(pyautogui, pyperclip, DEFAULT_PASSWORD)
    click_coord(pyautogui, config, ["ad", "coordinates", "confirm_password_field"])
    paste_text(pyautogui, pyperclip, DEFAULT_PASSWORD)
    click_coord(pyautogui, config, ["ad", "coordinates", "reset_password_ok_button"])
    pause(config, "medium_pause")


def automate_servicenow_closure(pyautogui, pyperclip, config, ticket):
    focus_edge(pyautogui, config)
    print("Updating ServiceNow work notes and status.")
    click_coord(pyautogui, config, ["servicenow", "coordinates", "work_notes_field"])
    paste_text(pyautogui, pyperclip, ticket.work_notes)
    click_coord(pyautogui, config, ["servicenow", "coordinates", "state_field"])
    hotkey(pyautogui, "ctrl", "a")
    paste_text(pyautogui, pyperclip, "Closed Complete")
    pyautogui.press("enter")
    pause(config, "short_pause")
    click_coord(pyautogui, config, ["servicenow", "coordinates", "update_button"])
    pause(config, "long_pause")


def calibrate(config):
    pyautogui, _ = require_rpa_modules()
    points = [
        ("ServiceNow first matching SCTASK row", ["servicenow", "coordinates", "first_matching_task_row"]),
        ("ServiceNow SCTASK Request Number / RITM field", ["servicenow", "coordinates", "request_number_field"]),
        ("ServiceNow RITM Departure Date field", ["servicenow", "coordinates", "ritm_departure_date_field"]),
        ("ServiceNow RITM Email forwarding checkbox", ["servicenow", "coordinates", "ritm_email_forwarding_checkbox"]),
        ("ServiceNow RITM Email Access checkbox", ["servicenow", "coordinates", "ritm_email_access_checkbox"]),
        ("ServiceNow RITM AD username field", ["servicenow", "coordinates", "ritm_ad_username_field"]),
        ("ServiceNow RITM full name field", ["servicenow", "coordinates", "ritm_full_name_field"]),
        ("ServiceNow Work notes field", ["servicenow", "coordinates", "work_notes_field"]),
        ("ServiceNow State/Status field", ["servicenow", "coordinates", "state_field"]),
        ("ServiceNow Update button", ["servicenow", "coordinates", "update_button"]),
        ("AD Find User search box", ["ad", "coordinates", "find_user_search_box"]),
        ("AD Find Now button", ["ad", "coordinates", "find_now_button"]),
        ("AD first search result", ["ad", "coordinates", "first_search_result"]),
        ("AD right-click Rename menu item", ["ad", "coordinates", "rename_menu_item"]),
        ("AD right-click Reset Password menu item", ["ad", "coordinates", "reset_password_menu_item"]),
        ("AD New password field", ["ad", "coordinates", "new_password_field"]),
        ("AD Confirm password field", ["ad", "coordinates", "confirm_password_field"]),
        ("AD Reset Password OK button", ["ad", "coordinates", "reset_password_ok_button"]),
    ]
    print("Calibration records mouse positions.")
    print("For each prompt, move the mouse to the requested target and press Enter here.")
    print("Do not click real Update/OK buttons while calibrating; just hover the mouse.")
    input("Press Enter to start calibration...")

    for label, path in points:
        input(f"Hover mouse over: {label}. Press Enter to capture.")
        x, y = pyautogui.position()
        section = config
        for key in path[:-1]:
            section = section[key]
        section[path[-1]] = [int(x), int(y)]
        print(f"Captured {label}: {x}, {y}")

    save_config(config)
    print(f"Saved calibration to {CONFIG_PATH}")


def main():
    parser = argparse.ArgumentParser(description="HSS desktop RPA bot")
    parser.add_argument("--calibrate", action="store_true", help="Record mouse positions into rpa_config.json")
    parser.add_argument("--dry-run", action="store_true", help="Calculate values only; do not click/type")
    parser.add_argument("--skip-ad", action="store_true", help="Skip Horizon/AD automation")
    parser.add_argument("--skip-servicenow", action="store_true", help="Skip ServiceNow closure automation")
    parser.add_argument("--manual", action="store_true", help="Ask for ticket details manually instead of reading ServiceNow screen")
    args = parser.parse_args()

    pyautogui, pyperclip = require_rpa_modules()
    config = load_config()

    if args.calibrate:
        calibrate(config)
        return

    if args.manual:
        ticket = collect_manual_ticket_data()
    else:
        ticket = collect_ticket_data_from_servicenow(pyautogui, pyperclip, config)
    print("")
    print("Automation target")
    print("-----------------")
    print("AD rename:      ", ticket.rename_value)
    print("Reset password: ", DEFAULT_PASSWORD)
    print("Work notes:")
    print(ticket.work_notes)
    print("")

    if args.dry_run:
        print("Dry run only. No clicks or typing performed.")
        return

    open_offboarding_tasks(pyautogui, pyperclip, config)
    if not args.skip_ad:
        automate_ad(pyautogui, pyperclip, config, ticket)
    if not args.skip_servicenow:
        automate_servicenow_closure(pyautogui, pyperclip, config, ticket)
    print("Automation completed.")


if __name__ == "__main__":
    main()
