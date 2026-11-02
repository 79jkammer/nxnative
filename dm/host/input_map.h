// The player's own controls, shared by the host (hle_hid.c) and the Mac front end (front_mac.m); pure C, checked by dm/tools/tests/test_input_map.py.
// DM_PAD_MAP=<physical>=<game>,... : which Switch button each button of a controller presses, by name (A B X Y LS RS L R ZL ZR PLUS MINUS LEFT UP RIGHT DOWN); DM_PAD_SWAP_AB=1 swaps A with B and X with Y first.
// DM_KEYMAP=<action>=<macOS key code>,... : which key does each action of the Mac keyboard, the buttons above plus SHAKE and the two sticks' directions (LSL LSU LSR LSD RSL RSU RSR RSD). The rest keep their keys.
// A name or number these tables do not know is skipped: a bad line leaves that one control as it was.
#pragma once
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { IM_BUTTONS = 16, IM_SHAKE = 16, IM_LSL = 17, IM_LSU, IM_LSR, IM_LSD, IM_RSL, IM_RSU, IM_RSR, IM_RSD, IM_ACTIONS };

static inline int im_action(const char *name, size_t n) {   // the numbers of the buttons are dm_input.h's bit numbers
    static const char *const names[IM_ACTIONS] = {"A", "B", "X", "Y", "LS", "RS", "L", "R", "ZL", "ZR", "PLUS", "MINUS", "LEFT", "UP", "RIGHT", "DOWN", "SHAKE", "LSL", "LSU", "LSR", "LSD", "RSL", "RSU", "RSR", "RSD"};
    for (int i = 0; i < IM_ACTIONS; i++) if (strlen(names[i]) == n && !strncmp(names[i], name, n)) return i;
    return -1;
}

// Runs body for each <key>=<value> of the list, with k_ / kn_ the key and v_ / vn_ the value.
#define IM_EACH(s, ...) \
    for (const char *p_ = (s); p_ && *p_;) { \
        const char *eq_ = strchr(p_, '='), *end_ = strchr(p_, ','); if (!end_) end_ = p_ + strlen(p_); \
        if (eq_ && eq_ < end_) { const char *k_ = p_, *v_ = eq_ + 1; size_t kn_ = (size_t)(eq_ - p_), vn_ = (size_t)(end_ - v_); (void)vn_; __VA_ARGS__ } \
        p_ = *end_ ? end_ + 1 : end_; \
    }

// out[i]: the Switch button that the controller's button i presses
static inline void pad_map_parse(const char *map, int swap_ab, uint8_t out[IM_BUTTONS]) {
    for (int i = 0; i < IM_BUTTONS; i++) out[i] = (uint8_t)i;
    if (swap_ab) { out[0] = 1; out[1] = 0; out[2] = 3; out[3] = 2; }
    IM_EACH(map, {
        int from = im_action(k_, kn_), to = im_action(v_, vn_);
        if (from >= 0 && from < IM_BUTTONS && to >= 0 && to < IM_BUTTONS) out[from] = (uint8_t)to;
    })
}

// Bits above the buttons (DM_BTN_SHAKE) pass through
static inline uint64_t pad_map_apply(uint64_t buttons, const uint8_t map[IM_BUTTONS]) {
    uint64_t out = buttons & ~(uint64_t)0xffff;
    for (int i = 0; i < IM_BUTTONS; i++) if (buttons >> i & 1) out |= 1ull << map[i];
    return out;
}

enum { IM_KEYS = 128 };
// table[key code]: the action + 1, 0 for none. The defaults are the keys front_mac.m documents.
static inline void key_map_defaults(uint8_t t[IM_KEYS]) {
    static const struct { uint8_t key, action; } d[] = {
        {38, 0}, {40, 1}, {32, 2}, {34, 3}, {3, 4}, {5, 5}, {12, 6}, {14, 7}, {6, 8}, {8, 9}, {36, 10}, {48, 11},   // J K U I, F G, Q E Z C, Return Tab
        {123, 12}, {126, 13}, {124, 14}, {125, 15}, {49, IM_SHAKE}, {0, IM_LSL}, {13, IM_LSU}, {2, IM_LSR}, {1, IM_LSD},   // the arrows, Space, A W D S
    };
    memset(t, 0, IM_KEYS);
    for (size_t i = 0; i < sizeof d / sizeof *d; i++) t[d[i].key] = (uint8_t)(d[i].action + 1);
}

// An action moved to a key leaves its old key, and the key's old action goes without one
static inline void key_map_parse(const char *map, uint8_t t[IM_KEYS]) {
    key_map_defaults(t);
    IM_EACH(map, {
        int action = im_action(k_, kn_); long key = strtol(v_, NULL, 10);
        if (action >= 0 && key >= 0 && key < IM_KEYS && vn_ > 0) {
            for (int i = 0; i < IM_KEYS; i++) if (t[i] == action + 1) t[i] = 0;
            t[key] = (uint8_t)(action + 1);
        }
    })
}
