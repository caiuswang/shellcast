# Background Session Persistence - Manual Test Cases

## Prerequisites
- Real iOS device (background tasks don't work reliably on Simulator)
- A reachable SSH host (e.g. via Tailscale)
- tmux installed on the remote host

---

## TC-1: Connection Survives Short Background

**Steps:**
1. Open ShellCast, connect to a host, enter a terminal session
2. Run a command (e.g. `top` or `htop`) so the terminal has visible output
3. Swipe home (app goes to background)
4. Wait ~5 seconds
5. Return to the app

**Expected:**
- Terminal is still connected, no reconnect overlay
- Output continues normally (e.g. `top` keeps updating)

---

## TC-2: Snapshot Captured on Background

**Steps:**
1. Connect to a host, enter a terminal session
2. Run `ls -la` so the terminal has visible content
3. Swipe home (app goes to background)
4. Return to app
5. Minimize the terminal (chevron down button)
6. Check the History tab

**Expected:**
- Session card shows an updated snapshot thumbnail matching what was on screen
- Snapshot timestamp shows "just now" or recent time

---

## TC-3: Auto-Reconnect After Long Background

**Steps:**
1. Connect to a host with tmux (`tmux attach -t <session>`)
2. Swipe home (app goes to background)
3. Wait **60+ seconds** (iOS will expire the background task and SSH may drop)
4. Return to the app

**Expected:**
- "Reconnecting..." overlay appears briefly
- Terminal auto-reconnects and shows "[Reconnected]"
- tmux session is restored with previous output intact

---

## TC-4: Session Marked Inactive on Expiration

**Steps:**
1. Connect to a host, enter a terminal session
2. Swipe home (app goes to background)
3. Wait **60+ seconds** for iOS to expire the background task
4. Force-quit the app (swipe up from app switcher)
5. Reopen ShellCast
6. Check the History tab

**Expected:**
- The session card is no longer marked as active (no green dot/border)
- Tapping it starts a fresh reconnection

---

## TC-5: Multiple Sessions Background Handling

**Steps:**
1. Connect to host A, enter terminal, run `echo "session A"`
2. Minimize terminal (chevron down)
3. Connect to host B (or same host, different tmux session), run `echo "session B"`
4. Swipe home (app goes to background)
5. Wait ~5 seconds, return to app
6. Minimize current terminal, check History tab

**Expected:**
- Both session cards have updated snapshots
- Both sessions remain active (green indicators)

---

## TC-6: Snapshot Not Captured When Disconnected

**Steps:**
1. Connect to a host, enter terminal
2. Trigger a disconnection (e.g. disable WiFi/Tailscale on the remote host)
3. Wait for "Connection Lost" overlay to appear
4. Swipe home (app goes to background)
5. Return to app, minimize terminal, check History tab

**Expected:**
- Snapshot is NOT updated (shows old snapshot or default icon)
- The disconnected overlay is still visible

---

## TC-7: Bridge Registration Lifecycle

**Steps:**
1. Connect to a host, enter terminal session
2. Minimize terminal (chevron down) — bridge should unregister
3. Resume the session from History tab — bridge should re-register
4. Swipe home while in terminal
5. Return to app

**Expected:**
- Snapshot is captured correctly after re-entering terminal
- No crashes or missing snapshots

---

## TC-8: Reconnect Button After Background Drop

**Steps:**
1. Connect to a host (without tmux)
2. Swipe home, wait 60+ seconds
3. Return to app — connection may have dropped

**Expected:**
- "Connection Lost" overlay with "Reconnect" button appears
- Tapping "Reconnect" establishes a new SSH connection
- Terminal is usable again after reconnection

---

## TC-9: Background Task Named Correctly (Xcode Debug)

**Steps:**
1. Run ShellCast from Xcode with console visible
2. Connect to a host, enter terminal
3. Swipe home

**Expected (in Xcode console):**
- Background task `ShellCast.KeepSSHAlive` is started
- No warnings about leaked or orphaned background tasks

---

## TC-10: Rapid Background/Foreground Cycling

**Steps:**
1. Connect to a host, enter terminal
2. Quickly swipe home then return (repeat 5-6 times rapidly)

**Expected:**
- No crashes
- Terminal remains connected
- No duplicate background tasks or leaked resources
