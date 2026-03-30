# Cancel Connection Attempt - Manual Test Cases

## Prerequisites
- Real iOS device
- A reachable SSH host and an unreachable host (or disconnect Tailscale to simulate timeout)

---

## TC-1: Cancel Button Visible During Connection

**Steps:**
1. Tap a saved connection to start connecting

**Expected:**
- Dark overlay appears with "Connecting..." spinner
- A "Cancel" button is visible below the spinner

---

## TC-2: Cancel Aborts Connection Without Error

**Steps:**
1. Tap a connection to an unreachable host (will timeout after 30s)
2. While "Connecting..." is shown, tap "Cancel"
3. Wait 30+ seconds

**Expected:**
- Overlay dismisses immediately on cancel
- No "Connection Error" alert appears, not even after 30s
- App returns to normal state, fully interactive

---

## TC-3: Cancel Then Connect Again

**Steps:**
1. Tap a connection (reachable or unreachable)
2. Tap "Cancel" while connecting
3. Tap the same connection again

**Expected:**
- Second connection attempt starts normally
- "Connecting..." overlay appears again with Cancel button
- If host is reachable, connection succeeds and proceeds to tmux browser

---

## TC-4: Cancel Then Connect to Different Host

**Steps:**
1. Tap connection A (unreachable host)
2. Tap "Cancel"
3. Tap connection B (reachable host)

**Expected:**
- Connection B proceeds normally
- No error from cancelled connection A appears
- Successfully enters tmux browser or terminal

---

## TC-5: Successful Connection (No Cancel)

**Steps:**
1. Tap a reachable connection
2. Do NOT tap Cancel — let it connect

**Expected:**
- Connection succeeds, proceeds to tmux browser
- Cancel button was visible during connection but not needed

---

## TC-6: Cancel Resume Session From History

**Steps:**
1. Go to History tab
2. Tap a session card to resume
3. Tap "Cancel" while "Connecting..." is shown

**Expected:**
- Overlay dismisses immediately
- No error alert appears
- History tab is still interactive

---

## TC-7: Connection Timeout Without Cancel

**Steps:**
1. Tap a connection to an unreachable host
2. Do NOT tap Cancel — wait for full timeout (~30s)

**Expected:**
- "Connection Error" alert appears with timeout message
- Tapping "OK" dismisses the alert
- App returns to normal state

---

## TC-8: Rapid Cancel and Reconnect

**Steps:**
1. Tap a connection
2. Immediately tap Cancel (within 1 second)
3. Tap the same connection again
4. Immediately tap Cancel again
5. Repeat 3-4 times

**Expected:**
- No crashes
- No lingering error alerts
- App remains responsive throughout
