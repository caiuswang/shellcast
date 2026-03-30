# Mosh Integration - Manual Test Cases

## Prerequisites
- Real iOS device with Tailscale VPN active
- A reachable SSH host with `mosh-server` installed
- A reachable SSH host WITHOUT `mosh-server` installed (for fallback tests)
- At least one saved connection configured as each type: SSH, Mosh, Auto

---

## TC-1: Mosh Connection — Basic

**Steps:**
1. Create/edit a connection, set Connection Type to "Mosh"
2. Tap the connection to connect
3. Browse tmux sessions normally
4. Select a tmux session (or "Connect without tmux")

**Expected:**
- SSH connects first, tmux browser shows sessions
- After selecting a session, terminal opens via Mosh (UDP)
- Terminal is responsive, can type commands
- Mosh prediction may show local echo (gray text before server confirms)

---

## TC-2: Mosh Connection — Server Not Installed

**Steps:**
1. Create a connection to a host WITHOUT `mosh-server`, set type to "Mosh"
2. Tap the connection

**Expected:**
- SSH connects, tmux browser appears
- After selecting a session, error alert: "mosh-server is not installed on the remote host"
- App remains usable, can go back

---

## TC-3: Auto Connection — Mosh Available

**Steps:**
1. Create a connection to a host WITH `mosh-server`, set type to "Auto"
2. Tap the connection
3. Select a tmux session

**Expected:**
- SSH connects, tmux browser works
- Terminal opens via Mosh (verify by checking local echo / prediction)
- Connection is resilient (see TC-7 for network tests)

---

## TC-4: Auto Connection — Mosh Fallback to SSH

**Steps:**
1. Create a connection to a host WITHOUT `mosh-server`, set type to "Auto"
2. Tap the connection
3. Select a tmux session

**Expected:**
- SSH connects, tmux browser works
- Mosh bootstrap fails silently, falls back to SSH
- Terminal opens normally via SSH PTY
- No error shown to user

---

## TC-5: SSH Connection — Unchanged Behavior

**Steps:**
1. Create a connection with type "SSH"
2. Connect and open a tmux session

**Expected:**
- Behaves exactly as before Mosh integration
- Terminal opens via SSH PTY
- Reconnect overlay works on connection loss
- Tmux switcher button works

---

## TC-6: Tmux Switcher — Mosh Session

**Steps:**
1. Connect via Mosh to a host with multiple tmux sessions
2. In the terminal, tap the tmux switcher button on the toolbar

**Expected:**
- Tmux switcher does NOT appear (not supported over Mosh)
- User can still switch tmux sessions via keyboard: `Ctrl-b` then `s` (list sessions) or `Ctrl-b` then window number

---

## TC-7: Mosh — WiFi to Cellular Handoff

**Steps:**
1. Connect via Mosh over WiFi
2. Verify terminal is working
3. Disable WiFi (switch to cellular)
4. Wait 5-10 seconds
5. Type a command

**Expected:**
- Brief pause while network switches
- Terminal resumes without any "Reconnecting" overlay
- Commands work normally — Mosh handles the transition via UDP

---

## TC-8: Mosh — Sleep and Wake

**Steps:**
1. Connect via Mosh
2. Verify terminal is working
3. Lock the phone (press power button)
4. Wait 30+ seconds
5. Unlock the phone and return to the app

**Expected:**
- Terminal resumes, possibly after brief sync
- No "Connection Lost" overlay (Mosh reconnects automatically)
- Server-side state is preserved (any commands that ran server-side appear)

---

## TC-9: Mosh — Long Sleep (Background Timeout)

**Steps:**
1. Connect via Mosh
2. Lock the phone
3. Wait 5+ minutes (iOS will suspend the app)
4. Return to the app

**Expected:**
- Mosh session may need to resync (brief delay)
- If Mosh recovers: terminal shows current server state
- If Mosh times out: "Connection Lost" overlay appears with Reconnect button

---

## TC-10: Mosh — Tmux Session with Attach

**Steps:**
1. On the server, create a tmux session: `tmux new -s test`
2. Run a long command: `top` or `watch date`
3. Detach: `Ctrl-b d`
4. On the phone, connect via Mosh
5. Select the "test" tmux session

**Expected:**
- Terminal shows the running command (`top` or `watch date`)
- Output updates in real-time
- Can interact with the program normally

---

## TC-11: Mosh — Disconnect and Resume from History

**Steps:**
1. Connect via Mosh to a tmux session
2. Minimize (chevron down button) — keep session alive
3. Go to History tab
4. Tap the session card to resume

**Expected:**
- New SSH + Mosh bootstrap occurs
- Tmux session re-attaches
- Terminal shows current state

---

## TC-12: Mosh — Close Button

**Steps:**
1. Connect via Mosh
2. Tap the X (close) button

**Expected:**
- Mosh session disconnects
- Session marked inactive in history
- No errors or crashes

---

## TC-13: Auto — Cancel During Mosh Bootstrap

**Steps:**
1. Create a connection with type "Auto"
2. Tap to connect
3. In tmux browser, select a session
4. Quickly tap Cancel if the connecting overlay appears during Mosh bootstrap

**Expected:**
- Connection attempt aborts cleanly
- No lingering errors
- Can reconnect normally

---

## TC-14: Mosh — Terminal Resize

**Steps:**
1. Connect via Mosh
2. Rotate the device (portrait to landscape)

**Expected:**
- Terminal resizes correctly
- Content reflows to new dimensions
- No rendering artifacts

---

## TC-15: Mosh — Rapid Input

**Steps:**
1. Connect via Mosh
2. Type rapidly or paste a long string

**Expected:**
- Mosh prediction shows gray local echo
- Characters appear immediately (before server confirmation)
- Final output matches what was typed
- No dropped characters
