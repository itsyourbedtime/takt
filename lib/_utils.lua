local utils = {}


local function default_engine_params(i)
    local default = {          
      lock = 0, offset = 0, rule = 0, retrig = 0, div = 5, 
      ---
      sample = i, note = 60, play_mode = 3, 
      quality = 5, amp = 0, pan = 0, detune_cents = 0,
      start_frame = 0, loop_start_frame = 0, end_frame = 2000000000, loop_end_frame = 2000000000,
      ---
      amp_env_attack = 0, amp_env_decay = 1, 
      amp_env_sustain = 1, amp_env_release = 0,
      --
      filter_type = 1, filter_freq = 20000, filter_resonance = 0,
      --
      freq_mod_lfo_1 = 0, freq_mod_lfo_2 = 0,
      amp_mod_lfo_1 = 0, filter_freq_mod_lfo_2 = 0,
      --
      reverb_send = -48, delay_send = -48, sidechain_send = -99
    }
    return default
  end
  
  local function default_midi_params(i)
    local default = {          
      lock = 0, offset = 0, rule = 0, retrig = 0, div = 5,
      ---
      device = 1,  note = 74 - i , length = 1,
      channel = 1, velocity = 100,  program_change = -1,
      ---
      cc_1 = 1, cc_1_val = -1, cc_2 = 2, cc_2_val = -1,
      cc_3 = 3, cc_3_val = -1, cc_4 = 4, cc_4_val = -1,
      cc_5 = 5, cc_5_val = -1, cc_6 = 6, cc_6_val = -1,
    }
    return default
  end
  
function utils.make_default_pattern()
  
    local default = { 
        bpm = 120, 
        sync_div = 0,
        track = { 
            mute = {}, 
            pos = {},
            start = {}, 
            len = {},
            div = {}, 
            cycle = {}, 
        },
    }
  
    for i = 1, 14 do   
        default.track.mute[i] = false
        default.track.pos[i] = 0
        default.track.start[i] = 1
        default.track.len[i] = 256
        default.track.div[i] = 5
        default.track.cycle[i] = 1
    end
  
  
    for l = 1, 7 do
        local m = l + 7
        
        default[l] = {}
        default[m] = {}
        default[l].params = {}
        default[m].params = {}
        default[l].params[tostring(l)] = default_engine_params(l)
        default[m].params[tostring(m)] = default_midi_params(m)
  
        for i=0,256 do
            default[l][i] = 0
            default[m][i] = 0
            default[l].params[i] = {}
            default[m].params[i] = {}
            setmetatable(default[l].params[i], {__index =  default[l].params[tostring(l)]})
            setmetatable(default[m].params[i], {__index =  default[m].params[tostring(m)]})
  
        end
    end
  
    return default
  
  end

return utils