-- takt v2
-- @its_your_bedtime
--
-- parameter locking sequencer
--

local engines = include('lib/engines')
local ui = include('lib/ui')
local linn = include('lib/linn')
local beatclock = require 'beatclock'
local music = require 'musicutil'
local fileselect = require('fileselect')
local textentry = require('textentry')
--
local midi_clock
local midi_out_devices = {}
local REC_CC = 38
--
local hold_time, down_time, blink = 0, 0, 1
local ALT, SHIFT, MOD, PATTERN_REC, K1_hold, K3_hold, ptn_copy, ptn_change_pending = false, false, false, false, false, false, false, false
local redraw_params, hold, holdmax, first, second = {}, {}, {}, {}, {}
local copy = { false, false }
--
local g = grid.connect()
local data = { pattern = 1, ui_index = 1, selected = { 1, false },  metaseq = { from = 1, to = 1 } }
local view = { steps_engine = true, steps_midi = false, notes_input = false, sampling = false, patterns = false } 
local choke = { 1, 2, 3, 4, 5, 6, 7, {},{},{},{},{},{},{}, ['8rt'] = {},['9rt'] = {},['10rt'] = {},['11rt'] = {}, ['12rt'] = {}, ['13rt'] = {},['14rt'] = {} }
local dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 2, [6] = 1.5, [7] = 1,} 
local midi_dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 1, [6] = 0.666, [7] = 0.545,} 
local sampling_actions = { [1] = engines.rec, [2] = engines.play, [3] = engines.play, [4] = engines.play, [5] = engines.save_and_load, [6] = engines.clear }
local lfo_1, lfo_2 = {[5] = true, [13] = true, [19] = true }, {[6] = true, [14] = true, [20] = true }

local param_ids = { 
  ['quality'] = "quality", ['start_frame'] = "start_frame", ['end_frame'] = "end_frame", ['loop_start_frame'] = "loop_start_frame", ['loop_end_frame'] = "loop_end_frame", ['freq_mod_lfo_1'] = "freq_mod_lfo_1", ['play_mode'] = 'play_mode',
  ['freq_mod_lfo_2'] = "freq_mod_lfo_2", ['filter_type'] = "filter_type", ['filter_freq'] = "filter_freq", ['filter_resonance'] = "filter_resonance", 
  ['filter_freq_mod_lfo_1'] = "filter_freq_mod_lfo_1", ['filter_freq_mod_lfo_2'] = "filter_freq_mod_lfo_2", ['pan'] = "pan", ['amp'] = "amp", 
  ['amp_mod_lfo_1'] = "amp_mod_lfo_1", ['amp_mod_lfo_2'] = "amp_mod_lfo_2", ['amp_env_attack'] = "amp_env_attack", ['amp_env_decay'] = "amp_env_decay", 
  ['amp_env_sustain'] = "amp_env_sustain", ['amp_env_release'] = "amp_env_release" 
  
}

local rules = {
  [0] =  { 'OFF', function() return true end },
  [1] =  { '10%', function() return 10 >= math.random(100) and true or false end },
  [2] =  { '20%', function() return 20 >= math.random(100) and true or false end },
  [3] =  { '30%', function() return 30 >= math.random(100) and true or false end },
  [4] =  { '50%', function() return 50 >= math.random(100) and true or false end },
  [5] =  { '60%', function() return 60 >= math.random(100) and true or false end },
  [6] =  { '70%', function() return 70 >= math.random(100) and true or false end },
  [7] =  { '90%', function() return 90 >= math.random(100) and true or false end },
  [8] =  {'/ 2', function(tr, step) return data[data.pattern].track.cycle[tr] % 2 == 0 and true or false  end },
  [9] =  {'/ 3', function(tr, step) return data[data.pattern].track.cycle[tr] % 3 == 0 and true or false  end },
  [10] = {'/ 4', function(tr, step) return data[data.pattern].track.cycle[tr] % 4 == 0 and true or false  end },
  [11] = {'/ 5', function(tr, step) return data[data.pattern].track.cycle[tr] % 5 == 0 and true or false  end },
  [12] = {'/ 6', function(tr, step) return data[data.pattern].track.cycle[tr] % 6 == 0 and true or false  end },
  [13] = {'/ 7', function(tr, step) return data[data.pattern].track.cycle[tr] % 7 == 0 and true or false  end },
  [14] = {'/ 8', function(tr, step) return data[data.pattern].track.cycle[tr] % 8 == 0 and true or false  end },
  [15] = {'RND NOTE', function(tr, step) 
    data[data.pattern][tr].params[step].note = math.random(24,120) return true end },
  [16] = {'+- NOTE', function(tr, step) 
    data[data.pattern][tr].params[step].note = util.clamp(data[data.pattern][tr].params[step].note + math.random(-20,20),24,120) return true end },
  [17] = {'RND START', function(tr, step)
    if tr < 8 then
      local max_frame = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval
      data[data.pattern][tr].params[step].start_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].loop_start = math.random(0, max_frame)
      end
    return true end },
  [18] = {'RND ST-EN', function(tr, step)
    if tr < 8 then
      local max_frame = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval
      data[data.pattern][tr].params[step].start_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].end_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].loop_start_frame = data[data.pattern][tr].params[step].start_frame
      data[data.pattern][tr].params[step].loop_end_frame = data[data.pattern][tr].params[step].end_frame
    end
    return true end },
}

--- utils, load/save

local function reset_positions()
  for i = 1, 14 do
    data[data.pattern].track.pos[i] = 0
  end
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, getmetatable(orig))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function load_project(pth)
  
  sequencer_metro:stop() 
  midi_clock:stop()
  engine.noteOffAll()
  redraw_metro:stop()

  if string.find(pth, '.tkt') ~= nil then
    local saved = tab.load(pth)
    if saved ~= nil then
      print("data found")
      for k,v in pairs(saved[2]) do 
        data[k] = v 
      end
      
      for t = 1, 16 do
        for l = 1, 7 do
          for k = 1, 256 do
            data[t][l].params[k] = saved[2][t][l].params[k]
           setmetatable(data[t][l].params[k], {__index =  data[t][l].params[tostring(l)]})
          end
        end
        
        for l = 8, 14 do
          for k = 1, 256 do
            data[t][l].params[k] = saved[2][t][l].params[k]
           setmetatable(data[t][l].params[k], {__index =  data[t][l].params[tostring(l)]})
          end
        end
      end
      
      if saved[1] then params:read(norns.state.data .. saved[1] .. ".pset") end
      reset_positions()
    else
      print("no data")
    end
  end
  redraw_metro:start()
end

local function save_project(txt)
  sequencer_metro:stop() 
  midi_clock:stop()
  redraw_metro:stop()
  engine.noteOffAll()
  if txt then
    tab.save({ txt, data }, norns.state.data .. txt ..".tkt")
    params:write( norns.state.data .. txt .. ".pset")
  else
    print("save cancel")
  end
  redraw_metro:start()
end

-- views

local function set_view(x)
    data.ui_index = 1 
    for k, v in pairs(view) do
      view[k] = k == x and true or false
    end
end

--- steps

local function get_step(x)
  return (x * 16) - 15
end

local function get_substep(tr, step)
    for s = (step*16) - 15, (step*16) + 15 do
      if data[data.pattern][tr][s] == 1 then
        return true
      end
    end
end

local function get_params(tr, step, lock)
    if not step then
      return data[data.pattern][tr].params[tostring(tr)]
    else
      local res = data[data.pattern][tr].params[step] 
      if lock then 
        res.default = data[data.pattern][tr].params[tostring(tr)]
      end
      return data[data.pattern][tr].params[step] -- res
    end
end

local function set_locks(step_param)
    for k, v in pairs(step_param) do
      if param_ids[k] ~= nil then
        params:set(k  .. '_' .. step_param.sample, v)
      end
    end
end
local function set_cc(step_param)
  for i = 1, 6 do
    local cc = step_param['cc_' .. i] 
    local val = step_param['cc_' .. i .. '_val'] 
    if val > -1 then
      midi_out_devices[step_param.device]:cc(cc, val, step_param.channel)
    end
  end
end

local function move_params(tr, src, dst )
  local s = data[data.pattern][tr].params[src]
  data[data.pattern][tr].params[dst] = s
end

local function clear_substeps(tr, s )
  for l = s, s + 15 do
    data[data.pattern][tr][l] = 0
    data[data.pattern][tr].params[l] = {}
    setmetatable(data[data.pattern][tr].params[l], {__index =  data[data.pattern][tr].params[tostring(tr)]})
  end
end

local function move_substep(tr, step, t)
   for s = step, step + 15 do
    data[data.pattern][tr][s] = (s == t) and 1 or 0
    move_params(tr, step, (s == t) and s or 1) 
   end
end

local function make_retrigs(tr, step, t)
    local t = 16 - t 
    local offset = data[data.pattern][tr].params[step].offset
    local params = data[data.pattern][tr].params[step]
    local st = step + 1

    for s = st + offset, (st + 14) - offset do
      if t == 16 then
        data[data.pattern][tr][s] = 0
      elseif s % t == 1 then
        data[data.pattern][tr][s] = s - offset == st and 1 or 0
      else
        data[data.pattern][tr][s] = ((s + offset) % t == 0) and 1 or 0
        data[data.pattern][tr].params[s] = params
      end
    end
end

local function have_substeps(tr, step)
    local st = get_step(step) 
    for s = st, st + 15 do
      if data[data.pattern][tr][s] == 1 then
        return s
      end
    end
end

local function place_note(tr, step, note )
  data[data.pattern][tr][step] = 1
  data[data.pattern][tr].params[step].lock = 1
  data[data.pattern][tr].params[step].note = data[data.pattern][tr].params[step].note
  data[data.pattern][tr].params[step].note = note
end

--- tracks 

local function is_lock()
    local src = data.selected
    if src[2] == false then
      return tostring(src[1])
    else
      return src[2]
    end
end

local function tr_change(tr)
  data.selected[1] = tr
  redraw_params[1] = get_params(tr)
  redraw_params[2] = redraw_params[1]
end

local function sync_tracks(tr)
    for i=1, 14 do
      if data[data.pattern].track.div[i] == data[data.pattern].track.div[tr] then
        data[data.pattern].track.pos[i] = data[data.pattern].track.pos[tr]
      end
    end
end

local function mute_track(tr)
  
  data[data.pattern].track.mute[tr] = not data[data.pattern].track.mute[tr]
  if data[data.pattern].track.mute[tr] and tr < 8 then 
    engine.noteOff(choke[tr])
  else
    print('midi mute')
  end

end

local function set_div(tr, div)
  data[data.pattern].track.div[tr] = div
  data[data.pattern][tr].params[tostring(tr)].div = div
  sync_tracks(tr)
end

local function set_bpm(n)
    data[data.pattern].bpm = n
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2)  / 16 --[[ppqn]] / 4 
    midi_clock:bpm_change( util.round(data[data.pattern].bpm / midi_dividers[util.clamp(data[data.pattern].sync_div, 1, 7)]))
end

local function set_loop(tr, start, len)
    data[data.pattern].track.start[tr] = get_step(start)
    data[data.pattern].track.len[tr] = get_step(len) + 15
    sync_tracks(tr)
end

local function get_tr_start( tr )
  return math.ceil(data[data.pattern].track.start[tr] / 16)
end

local function get_tr_len( tr )
  return math.ceil(data[data.pattern].track.len[tr] / 16)
end

local function get_sample_len(tr, s)
  local maxval = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.maxval
  data[data.pattern][tr].params[s].end_frame = maxval
  data[data.pattern][tr].params[s].loop_end_frame = maxval
end

--- copy / settings

local function copy_step(src, dst)
    for i = 0, 15 do
      data[data.pattern][dst[1]][get_step(dst[2]) + i] = data[data.pattern][src[1]][get_step(src[2]) + i]
        for k,v in pairs(data[data.pattern][src[1]].params[get_step(src[2]) + i]) do
          data[data.pattern][dst[1]].params[get_step(dst[2]) + i][k]  = v
        end
    end
end

local function copy_pattern(src, dst)
    data[dst] = deepcopy(data[src])
end

local function open_sample_settings()
    local p = is_lock()
    norns.menu.toggle(true)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 25 +(( data[data.pattern][data.selected[1]].params[p].sample - 1 ) * 94 ))
end

local function open_lfo_settings(i)
     norns.menu.toggle(true)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 10 + (i*4))
end

local function change_filter_type()
    local tr = data.selected[1]
    local p = is_lock()
    data[data.pattern][tr].params[p].ftype =  data[data.pattern][tr].params[p].ftype
    data[data.pattern][tr].params[p].ftype = (data[data.pattern][tr].params[p].ftype % 2 ) + 1
end

local function choke_group(tr, sample)
  if sample == choke[tr] then
      engine.noteOff(tr)
  end
end

local function kill_all_midi()
  for id = 1, 4 do
    for ch = 1, 16 do
      for note = 0, 127 do
         midi_out_devices[id]:note_off(note, 0, ch)
      end
    end
  end
end

local function notes_off_midi()
  for i = 8, 14 do
      if choke[i][6] then
        midi_out_devices[choke[i][1]]:note_off(choke[i][2], choke[i][3], choke[i][4])
      end
  end
end

-- seq

local function metaseq(counter)
    if data[data.pattern].track.pos[1] == data[data.pattern].track.len[1] - 1 then
      
        if ptn_change_pending then
          data.pattern = ptn_change_pending
          ptn_change_pending = false
        end
        
      if (data.metaseq.to and data.metaseq.from) then
        data.pattern = data.pattern < data.metaseq.to and data.pattern + 1 or data.metaseq.from
        set_bpm(data[data.pattern].bpm)
      end
    end
end

local function advance_step(tr, counter)
  local start = data[data.pattern].track.start[tr]
  local len = data[data.pattern].track.len[tr]
  data[data.pattern].track.pos[tr] = util.clamp((data[data.pattern].track.pos[tr] + 1) % (len ), start, len) -- voice pos
  data[data.pattern].track.cycle[tr] = counter % 256 == 0 and data[data.pattern].track.cycle[tr] + 1 or data[data.pattern].track.cycle[tr]  --data[data.pattern].track.cycle[tr]
end

local function seqrun(counter)
  for tr = 1, 14 do

      local div = data[data.pattern].track.div[tr]
      
      if (div ~= 6 and counter % dividers[div] == 0) 
      or (div == 6 and counter % dividers[div] >= 0.5) then

        advance_step(tr, counter)
        
        local mute = data[data.pattern].track.mute[tr]
        local pos = data[data.pattern].track.pos[tr]
        local trig = data[data.pattern][tr][pos]
        
        if tr > 7 and choke[tr][6] then
          if pos > choke[tr][5] + choke[tr][6] then
            midi_out_devices[choke[tr][1]]:note_off(choke[tr][2], choke[tr][3], choke[tr][4])
          end
        end
        
        if trig == 1 and not mute then
          
          set_locks(data[data.pattern][tr].params[tostring(tr)])
          
          local step_param = get_params(tr, pos, true)
          
          data[data.pattern].track.div[tr] = step_param.div ~= data[data.pattern].track.div[tr] and step_param.div or data[data.pattern].track.div[tr]

          if rules[step_param.rule][2](tr, pos) then 
            
            step_param = step_param.lock ~= 1 and get_params(tr) or step_param
            
            if tr == data.selected[1] then 
              redraw_params[1] = step_param
              redraw_params[2] = step_param
            end
            
            if tr < 8 then
              
              set_locks(step_param)
              choke_group(tr, step_param.sample)
              engine.noteOn(tr, music.note_num_to_freq(step_param.note), 1, step_param.sample)
              choke[tr] = step_param.sample
              
            else
              
              set_cc(step_param)
              
              if step_param.program_change >= 0 then
                midi_out_devices[step_param.device]:program_change(step_param.program_change, step_param.channel)
              end

              midi_out_devices[step_param.device]:note_on( step_param.note, step_param.velocity, step_param.channel )
              choke[tr] = { step_param.device, step_param.note, step_param.velocity, step_param.channel, pos, step_param.length} 
            end
          end
       end
    end
  end
  
end

local function midi_event(d)
  
  local msg = midi.to_msg(d)
  local tr = data.selected[1] 

  local pos = data[data.pattern].track.pos[tr]
  
  -- REC TOGGLE
  if msg.cc == REC_CC and msg.val == 127 then
    PATTERN_REC = not PATTERN_REC
  -- Note off
  elseif msg.type == "note_off" then
    --engine.noteOff(tr)
  -- Note on
  elseif msg.type == "note_on" then
    if not view.sampling then
      engine.noteOff(tr)
      engine.noteOn(tr, music.note_num_to_freq(msg.note), msg.vel / 127, data[data.pattern][tr].params[tostring(tr)].sample)
      if sequencer_metro.is_running and PATTERN_REC then
        place_note(tr, pos, msg.note)
      end
    end
  end

end
---

local track_params = {
  [-6] = function(tr, s, d) -- ptn
      data.pattern = (util.clamp(data.pattern + d, 1, 16))
      data.metaseq.from = false --data.pattern
      data.metaseq.to = false --data.pattern
  end,
  [-5] = function(tr, s, d) -- rnd
        local offset = view.steps_midi and 7 or 0
        data.selected[1] = util.clamp(data.selected[1] + d, 1 + offset, 7 + offset)
        tr_change(data.selected[1])
  end,
  [-4] = function(tr, s, d) -- global bpm
      set_bpm(util.clamp(data[data.pattern].bpm + d, 1, 999))
  end,
  [-3] = function(tr, s, d) -- track scale
    
      local div = data[data.pattern].track.div[tr]
      data[data.pattern].track.div[tr] = util.clamp(data[data.pattern].track.div[tr] + d, 1, 7)
      data[data.pattern][tr].params[tostring(tr)].div = data[data.pattern].track.div[tr]
      if div ~= data[data.pattern].track.div[tr] then sync_tracks(tr) end
      
  end,
  [-2] = function(tr, s, d) -- midi out bpm scale
      data[data.pattern].sync_div = util.clamp(data[data.pattern].sync_div + d, 0, 7)
      if data[data.pattern].sync_div == 0 then midi_clock.send = false else midi_clock.send = true end
  end,
}
 
local midi_step_params = {

  [1] = function(tr, s, d) -- note
      data[data.pattern][tr].params[s].note = util.clamp(data[data.pattern][tr].params[s].note + d, 25, 127)
  end,
  [2] = function(tr, s, d) -- velocity
      data[data.pattern][tr].params[s].velocity = util.clamp(data[data.pattern][tr].params[s].velocity + d, 0, 127)
  end,
  [3] = function(tr, s, d) -- length
      data[data.pattern][tr].params[s].length = util.clamp(data[data.pattern][tr].params[s].length + d, 1, 256)
  end,
  [4] = function(tr, s, d) -- channel
      data[data.pattern][tr].params[s].channel = util.clamp(data[data.pattern][tr].params[s].channel + d, 1, 16)
  end,
  [5] = function(tr, s, d) -- device
      data[data.pattern][tr].params[s].device = util.clamp(data[data.pattern][tr].params[s].device + d, 1, 4)
  end,
  [6] = function(tr, s, d) -- pgm
      data[data.pattern][tr].params[s].program_change = util.clamp(data[data.pattern][tr].params[s].program_change + d, -1, 127)
  end,
  
  [7] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_1_val = util.clamp(data[data.pattern][tr].params[s].cc_1_val + d, -1, 127)
  end,
  [8] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_2_val = util.clamp(data[data.pattern][tr].params[s].cc_2_val + d, -1, 127)
  end,
  [9] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_3_val = util.clamp(data[data.pattern][tr].params[s].cc_3_val + d, -1, 127)
  end,
  [10] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_4_val = util.clamp(data[data.pattern][tr].params[s].cc_4_val + d, -1, 127)
  end,
  [11] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_5_val = util.clamp(data[data.pattern][tr].params[s].cc_5_val + d, -1, 127)
  end,
  [12] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_6_val = util.clamp(data[data.pattern][tr].params[s].cc_6_val + d, -1, 127)
  end,
  
  [13] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_1 = util.clamp(data[data.pattern][tr].params[s].cc_1 + d, 1, 127)
  end,
  [14] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_2 = util.clamp(data[data.pattern][tr].params[s].cc_2 + d, 1, 127)
  end,
  [15] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_3 = util.clamp(data[data.pattern][tr].params[s].cc_3 + d, 1, 127)
  end,
  [16] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_4 = util.clamp(data[data.pattern][tr].params[s].cc_4 + d, 1, 127)
  end,
  [17] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_5 = util.clamp(data[data.pattern][tr].params[s].cc_5 + d, 1, 127)
  end,
  [18] = function(tr, s, d) -- 
      data[data.pattern][tr].params[s].cc_6 = util.clamp(data[data.pattern][tr].params[s].cc_6 + d, 1, 127)
  end,

}

local step_params = {
  [1] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].sample = util.clamp(data[data.pattern][tr].params[s].sample + d, 1, 100)
  end, 
  [2] = function(tr, s, d) -- note
      data[data.pattern][tr].params[s].note = util.clamp(data[data.pattern][tr].params[s].note + d, 25, 127)
  end,
  [3] = function(tr, s, d) -- start
      local sample = data[data.pattern][tr].params[s].sample
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval 
      data[data.pattern][tr].params[s].start_frame = util.clamp(data[data.pattern][tr].params[s].start_frame + ((d) * (length / (K3_hold and 1000 or 100))), 0,  length)
      data[data.pattern][tr].params[s].lool_start_frame = data[data.pattern][tr].params[s].lool_start_frame
  end,
  [4] = function(tr, s, d) -- len
      local sample = data[data.pattern][tr].params[s].sample
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval
      data[data.pattern][tr].params[s].end_frame = util.clamp(data[data.pattern][tr].params[s].end_frame + ((d) * (length / (K3_hold and 1000 or 100))), 0, length)
      data[data.pattern][tr].params[s].loop_end_frame = data[data.pattern][tr].params[s].loop_end_frame
   end,
  [5] = function(tr, s, d) -- freq mod lfo 1 freq_lfo1
      data[data.pattern][tr].params[s].freq_mod_lfo_1 = util.clamp(data[data.pattern][tr].params[s].freq_mod_lfo_1 + d / 100, 0, 1)
  end,
  [6] = function(tr, s, d) -- freq mod lfo 2
        data[data.pattern][tr].params[s].freq_mod_lfo_2 = util.clamp(data[data.pattern][tr].params[s].freq_mod_lfo_2 + d / 100, 0, 1)
  end,
  [7] = function(tr, s, d) -- volume
        data[data.pattern][tr].params[s].amp = util.clamp(data[data.pattern][tr].params[s].amp + d / 10  , -48, 16)
  end,
  [8] = function(tr, s, d) -- pan
        data[data.pattern][tr].params[s].pan = util.clamp(data[data.pattern][tr].params[s].pan + d / 10 , -1, 1)
  end,
  [9] = function(tr, s, d) -- atk
    data[data.pattern][tr].params[s].amp_env_attack = util.clamp(data[data.pattern][tr].params[s].amp_env_attack + d / 50, 0, 5)
  end,
  [10] = function(tr, s, d) -- dec
      data[data.pattern][tr].params[s].amp_env_decay = util.clamp(data[data.pattern][tr].params[s].amp_env_decay + d / 50, 0.01, 5)
  end,
  [11] = function(tr, s, d) -- sus
      data[data.pattern][tr].params[s].amp_env_sustain = util.clamp(data[data.pattern][tr].params[s].amp_env_sustain + d / 10, 0, 1)
  end,
  [12] = function(tr, s, d) -- rel
      data[data.pattern][tr].params[s].amp_env_release = util.clamp(data[data.pattern][tr].params[s].amp_env_release + d / 10, 0, 10)
  end,
  [13] = function(tr, s, d) -- amp mod lfo 1
        data[data.pattern][tr].params[s].amp_mod_lfo_1 = util.clamp(data[data.pattern][tr].params[s].amp_mod_lfo_1 + d / 100, 0, 1)
  end,
  [14] = function(tr, s, d) -- amp mod lfo 2
        data[data.pattern][tr].params[s].amp_mod_lfo_2 = util.clamp(data[data.pattern][tr].params[s].amp_mod_lfo_2 + d / 100, 0, 1)
  end,
  [15] = function(tr, s, d) -- sample rate
      data[data.pattern][tr].params[s].quality = util.clamp(data[data.pattern][tr].params[s].quality + d, 1, 5)
  end,
  [16] = function(tr, s, d) -- mode
      data[data.pattern][tr].params[s].play_mode = util.clamp(data[data.pattern][tr].params[s].play_mode + d, 1, 4)
  end,
  [17] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].filter_freq = util.clamp(data[data.pattern][tr].params[s].filter_freq + (d * 200), 0, 20000)
  end,
  [18] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].filter_resonance = util.clamp(data[data.pattern][tr].params[s].filter_resonance + d / 10, 0, 1)
  end,
  [19] = function(tr, s, d) -- filter cutoff mod lfo 1
        data[data.pattern][tr].params[s].filter_freq_mod_lfo_1 = util.clamp(data[data.pattern][tr].params[s].filter_freq_mod_lfo_1 + d / 100, 0, 1)
  end,
  [20] = function(tr, s, d) -- filter cutoff mod lfo 2
        data[data.pattern][tr].params[s].filter_freq_mod_lfo_2 = util.clamp(data[data.pattern][tr].params[s].filter_freq_mod_lfo_2 + d / 100, 0, 1)
  end,
  
}

local sampling_params = {
  [-1] = function(d)engines.sc.mode = util.clamp(engines.sc.mode + d, 1, 4) engines.set_mode() end,
  [0] = function(d) engines.sc.source = util.clamp(engines.sc.source + d, 1, 2) engines.set_source() end,
  [5] = function(d) engines.sc.slot = util.clamp(engines.sc.slot + d, 1, 100) end,
  [3] = function(d) engines.sc.start = util.clamp(engines.sc.start + d / 10, 0, engines.sc.length) engines.set_start(engines.sc.start) end,
  [4] = function(d) engines.sc.length = util.clamp(engines.sc.length + d / 10, engines.sc.start, engines.sc.max_length) end,
  [6] = function(d) end, --play
  [1] = function(d) end, --save
  [2] = function(d) end, --clear
  [7] = function(d) end, --clear
}

local trig_params = {  
  [-3] = function(tr, s, d) -- 
    data[data.pattern][tr].params[s].div = util.clamp(data[data.pattern][tr].params[s].div + d, 1, 7)
  end,
  [-2] = function(tr, s, d) -- rule
      data[data.pattern][tr].params[s].rule = util.clamp(data[data.pattern][tr].params[s].rule + d, 0, #rules)
  end,
  [-1] = function(tr, s, d) -- retrig
      data[data.pattern][tr].params[s].retrig = util.clamp(data[data.pattern][tr].params[s].retrig + d, 0, 15)
      make_retrigs(tr, s, data[data.pattern][tr].params[s].retrig)
  end,
  [0] = function(tr, s, d) -- offset
      data[data.pattern][tr].params[s + data[data.pattern][tr].params[s].offset].offset = util.clamp(data[data.pattern][tr].params[s].offset + d, 0, 15)
      move_substep(tr, s, s + data[data.pattern][tr].params[s].offset)
      data[data.pattern][tr].params[s].retrig = 0
  end,
}

local controls = {
  [1] = function(z) -- start / stop, 
      if z == 1 then
        if sequencer_metro.is_running then 
          sequencer_metro:stop() 
          midi_clock:stop()
          notes_off_midi()
        else 
          sequencer_metro:start() 
          midi_clock:start()
        end
        if MOD then
          engine.noteOffAll() 
          reset_positions()
          kill_all_midi()
        end
      end
    end,
  [3] = function(z)  if view.notes_input and z == 1 and sequencer_metro.is_running then PATTERN_REC = not PATTERN_REC end end,
  [5] = function(z)  if z == 1 then if not view.notes_input then set_view('steps_engine') PATTERN_REC = false end tr_change(1)  end end,
  [6] = function(z)  if z == 1 then  if not view.notes_input then set_view('steps_midi') PATTERN_REC = false end tr_change(8)  end end,
  [8] = function(z)  if z == 1 then set_view(view.notes_input and (data.selected[1] < 8 and 'steps_engine' or 'steps_midi') or 'notes_input') end end,
  [10] = function(z) if z == 1 then set_view(view.sampling and 'steps_engine' or 'sampling') end  end,
  [11] = function(z) if z == 1 then set_view(view.patterns and 'steps_engine' or 'patterns') end end,
  [13] = function(z) MOD = z == 1 and true or false if z == 0 then copy = { false, false } end end,
  [15] = function(z) ALT = z == 1 and true or false end,
  [16] = function(z) SHIFT = z == 1 and true or false end,
}

function init()

  for i = 1, 4 do
      midi_out_devices[i] = midi.connect(i)
      midi_out_devices[i].event = midi_event
  end
    
  math.randomseed(os.time())

    params:add_trigger('save_p', "< Save project" )
    params:set_action('save_p', function(x) textentry.enter(save_project,  'new') end)
    params:add_trigger('load_p', "> Load project" )
    params:set_action('load_p', function(x) fileselect.enter(norns.state.data, load_project) end)
    params:add_trigger('new', "+ New" )
    params:set_action('new', function(x) init() end)
    params:add_separator()


    for t = 1, 16 do
      data[t] = { bpm = 120, sync_div = 5,
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
        hold[i] = 0
        holdmax[i] = 0
        first[i] = 0
        second[i] = 0
        
        data[t].track.mute[i] = false
        data[t].track.pos[i] = 0
        data[t].track.start[i] = 1
        data[t].track.len[i] = 256
        data[t].track.div[i] = 5
        data[t].track.cycle[i] = 1
      end
      
      
      for l = 1, 7 do
        local m = l + 7
        
        data[t][l] = {}
        data[t][m] = {}
        data[t][l].params = {}
        data[t][m].params = {}
        
        data[t][l].params[tostring(l)] = {
            ---
            lock = 0, offset = 0, rule = 0, retrig = 0, div = 5, 
            ---
            sample = l, note = 60, play_mode = 3, quality = 5, amp = 0, pan = 0, 
            start_frame = 0, loop_start_frame = 0, end_frame = 99999999, loop_end_frame = 99999999,
            ---
            amp_env_attack = 0, amp_env_decay = 1, 
            amp_env_sustain = 1, amp_env_release = 0,
            --
            filter_type = 1, filter_freq = 20000, filter_resonance = 0,
            --
            freq_mod_lfo_1 = 0, freq_mod_lfo_2 = 0,
            amp_mod_lfo_1 = 0, amp_mod_lfo_2 = 0,
            filter_freq_mod_lfo_1 = 0, filter_freq_mod_lfo_2 = 0,
        }
    
        data[t][m].params[tostring(m)] = {
            --
            lock = 0, offset = 0, rule = 0, retrig = 0, div = 5,
            ---
            device = 1,  note = 74 - m, length = 1,
            channel = 1, velocity = 100,  program_change = -1,
            ---
            cc_1 = 1, cc_1_val = -1, cc_2 = 2, cc_2_val = -1,
            cc_3 = 3, cc_3_val = -1, cc_4 = 4, cc_4_val = -1,
            cc_5 = 5, cc_5_val = -1, cc_6 = 6, cc_6_val = -1,
            --
        }

        for i=0,256 do
          data[t][l][i] = 0
          data[t][m][i] = 0
          
          data[t][l].params[i] = {}
          data[t][m].params[i] = {}
          
          setmetatable(data[t][l].params[i], {__index =  data[t][l].params[tostring(l)]})
          setmetatable(data[t][m].params[i], {__index =  data[t][m].params[tostring(m)]})

        end
      end
        
    end
    
    
    redraw_params[1] = data[1][1].params[tostring(1)]
    redraw_params[2] = data[1][1].params[tostring(1)]

    sequencer_metro = metro.init()
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2) / 16 --[[ppqn]] / 4 
    sequencer_metro.event = function(stage) seqrun(stage) if stage % 2 == 0 then metaseq(stage) end end

    redraw_metro = metro.init(function(stage) redraw() g:redraw() blink = (blink + 1) % 17 end, 1/30)
    redraw_metro:start()
    midi_clock = beatclock:new()
    midi_clock.on_step = function() end
    midi_clock:bpm_change(data[data.pattern].bpm * dividers[data[data.pattern].sync_div])
    midi_clock.send = false

    engines.init()
    ui.init()
end

function enc(n,d)
  norns.encoders.set_sens(1,4)
  norns.encoders.set_sens(2,4)
  norns.encoders.set_sens(3,4)
  norns.encoders.set_accel(1, false)
  norns.encoders.set_accel(2, false)
  norns.encoders.set_accel(3, true)

  local tr = data.selected[1]
  local s = data.selected[2] and data.selected[2] or tostring(tr)
  
  if n == 1 then
      
      local offset = data.selected[1] > 7 and 7 or 0
      data.selected[1] = util.clamp(data.selected[1] + d, 1 + offset, 7 + offset)
      tr_change(data.selected[1])
      
  elseif n == 2 then
    
    if not view.sampling then
      if not K1_hold then 
        data.ui_index = util.clamp(data.ui_index + d, not data.selected[2] and 1 or -3, view.steps_midi and 18 or 20)
      else
        data.ui_index = util.clamp(data.ui_index + d, -6, -2)
      end
    else
      if not engines.sc.rec then
        data.ui_index = util.clamp(data.ui_index + d, -1, 6)      
      end
    end
  elseif n == 3 then
    if not view.sampling then
      
      local p = is_lock()
      local t = type(p) == 'number' and get_step(p) or p

      data[data.pattern][tr].params[t].lock = data.selected[2] and 1 or 0
      
      redraw_params[1] = get_params(tr, is_lock())
      redraw_params[2] = redraw_params[1] 

      if K1_hold then
        track_params[data.ui_index](tr, p, d)
      else
        
          local params_t = data.ui_index < 1 and trig_params or tr < 8 and step_params or tr > 7 and midi_step_params
      
          if type(p) == 'string' then
            params_t[data.ui_index](tr, p, d)
          else
            if data.ui_index > 0 then
              for i = t, t + 15 do params_t[data.ui_index](tr, i, d) end
            else
              params_t[data.ui_index](tr, t, d)
            end
          end

      if view.notes_input then set_locks(get_params(tr)) end
      end
    else
      sampling_params[data.ui_index](d)
    end
  end
end

function key(n,z)
  
  K1_hold = (n == 1 and z == 1 and true) or false
  K3_hold = (n == 3 and z == 1 and true) or false
  if n == 1 then
    if K1_hold and not view.sampling then 
      data.ui_index = -4 
    else 
      data.ui_index = 1 
    end
  elseif n == 3 then
    if view.sampling then
        sampling_actions[data.ui_index](z)
    else
      if data.ui_index == 1 and z == 1 then
        open_sample_settings()
      elseif (data.ui_index == 17 or data.ui_index == 18) and z == 1 then
        change_filter_type()
      elseif lfo_1[data.ui_index] then
        open_lfo_settings(1)
      elseif lfo_2[data.ui_index] then
        open_lfo_settings(2)
      end
    end
  end
end

function redraw()

  local tr = data.selected[1]
  local pos = data[data.pattern].track.pos[tr]
  local params_data = get_params(tr, sequencer_metro.is_running and pos or false, true)
  
  if data.selected[2] then
    redraw_params[1] = get_params(data.selected[1], get_step(data.selected[2]), true)
  elseif not data.selected[2] then
    redraw_params[1] = redraw_params[2]
  end
  
  -- length hack
  if params_data.end_frame == 99999999 and engines.get_meta(params_data.sample).waveform[2] ~= nil then
    get_sample_len(tr, is_lock())
  end

  screen.clear()
  
  ui.head(redraw_params[1], data, view, K1_hold, rules, PATTERN_REC)
  
  if view.sampling then 
    local pos = engines.get_pos()
    ui.sampling(engines.sc, data.ui_index, pos)

  else
    if data.selected[1] < 8 then
      local meta = engines.get_meta(params_data.sample)
      ui.main_screen(redraw_params[1], data.ui_index, meta)
    else
      ui.midi_screen(redraw_params[1], data.ui_index, data[data.pattern].track, data[data.pattern])
    end
  end
  
  screen.update()

end

function g.key(x, y, z)
  screen.ping()
  
  if view.notes_input and not ALT and not SHIFT then
      local tr = data.selected[1]
      local device = data[data.pattern][tr].params[tr].device
      local note = linn.grid_key(x, y, z, device and midi_out_devices[device])
      local pos = data[data.pattern].track.pos[tr]
      
      if note then 
        if tr < 8 then
          engine.noteOn(data.selected[1], music.note_num_to_freq(note), 1, data[data.pattern][data.selected[1]].params[tr].sample)
        end
        if sequencer_metro.is_running and PATTERN_REC then 
            place_note(tr, pos, note )
        end
      end           
  end    

  if y < 8 then
    local held
    local cond = have_substeps(y, x) 

    if z==1 and hold[y] then
      holdmax[y] = 0
    end
    hold[y] = hold[y] + (z * 2 - 1)
    if hold[y] > holdmax[y] then
      holdmax[y] = hold[y]
    end
    if not view.patterns then
      local y = data.selected[1] > 7 and y + 7 or y
      
      if SHIFT then
        if z == 1 then
          if x == 16 then
              mute_track(y)
          else
            if x < 8 then
              set_div(y, x)
            end
          end
        end
      elseif ALT then 
          if hold[y] == 1 then
            first[y] = x
          elseif hold[y] == 2 then
            second[y] = x
            set_loop(y, first[y], second[y])
          end
      elseif MOD then
        if not copy[1] then 
          copy = { y, x }
        else
          copy_step(copy, {y, x})
        end
      elseif not view.notes_input then
        cond = have_substeps(y, x) 
        data.selected = { y, z == 1 and x or false }
        if not data.selected[2] then tr_change(y) end
        if not data.selected[2] and data.ui_index < 1 then data.ui_index = 1 end
       if z == 1 then
          down_time = util.time()
        else
          hold_time = util.time() - down_time
          held = hold_time > 0.2 and true or false
          x = get_step(x)
          if not cond then
            data[data.pattern][y][x] = 1
          elseif cond and not held then
            clear_substeps(y, x)
            data.selected = { y, false }
            tr_change(y)
          end
        end        
      end
    
      
    elseif view.patterns then
      if y == 1 and z == 1 then
        if MOD then 
            
            if not ptn_copy then 
              ptn_copy = x
            else
              copy_pattern(ptn_copy, x)
            end
            
        else
          
          if hold[y] == 1 then
            first[y] = x
            
            ptn_change_pending = x
            data.metaseq.from = false
            data.metaseq.to = false
            ptn_copy = false
          elseif hold[y] == 2 then
            second[y] = x

            data.metaseq.from = first[y]
            data.metaseq.to = second[y]
            
          end
        end
      end
    end
  
  else
    
    if controls[x] then
      controls[x](z)
    end
    
    if z == 1 then
      if view.sampling then
        ui.start_polls()
      else 
        ui.stop_polls()
      end
    end

  end
  
end

function g.redraw()
  local glow = util.clamp(blink, 5, 15)
  
  g:all(0)
  
  if view.notes_input and (not ALT and not SHIFT) then 
      linn.grid_redraw(g)
  end
  
  for y = 1, 7 do 
    for x = 1, 16 do 
      if not view.patterns then
        local yy = data.selected[1] > 7 and y + 7 or y 
        if SHIFT then
                        
            if y < 8 and x < 8 then
              g:led(x, y, x == 5 and 6 or 3)
            end
            
            g:led(data[data.pattern].track.div[yy], y, 15)
            g:led(16, y, data[data.pattern].track.mute[yy] and 15 or 6 )

        elseif ALT then
          
            local t_start = get_tr_start(yy)
            local t_len  = get_tr_len(yy)
            if x >= t_start and x <= t_len then
              g:led(x, y, 3)
            end
        
        elseif not SHIFT and not view.notes_input then
          -- main
          local substeps = have_substeps(yy, x)
          
          if substeps then 
            
              local t_start = get_tr_start(yy)
              local t_len  = get_tr_len(yy)
              local level = data.selected[1] == yy and data.selected[2] == x and 15 
              or (x < t_start or x > t_len) and 5
              or data[data.pattern].track.mute[yy] and 5
              or 10
              
              g:led(x, y, level ) 
          end
        end

      else
          -- patterns
          local level =
          x == ptn_change_pending  and sequencer_metro.is_running and  util.clamp(blink, 5, 14)
          or (data.metaseq.from and data.metaseq.to) and x == data.pattern and  util.clamp(blink, 5, 14)
          or (x >= (data.metaseq.from and data.metaseq.from or data.pattern) and x <= (data.metaseq.to and data.metaseq.to or data.pattern)) and 9 
          or data.pattern == x and 15 
          or 3
          
          g:led(x, 1, level)

      end
    end
    -- playhead
    if (view.notes_input and  ALT ) or (not view.patterns and not view.notes_input) and sequencer_metro.is_running and not SHIFT then
      local yy = view.steps_midi and y + 7 or y 
      local pos = math.ceil(data[data.pattern].track.pos[yy] / 16)
      local level = have_substeps(yy, pos) and 15 or 6
      if not data[data.pattern].track.mute[yy] then g:led(pos, y, level) end
    end
  end
  
  g:led(1, 8,  sequencer_metro.is_running and 15 or 6 )
  
  g:led(3, 8,  (view.notes_input and PATTERN_REC) and glow or view.notes_input and 6 or 0)
  g:led(5, 8,  (view.notes_input and data.selected[1] < 8 or view.steps_engine) and 15  or  6)
  g:led(6, 8,  (view.notes_input and data.selected[1] > 7 or view.steps_midi) and 15  or  6)
  
  g:led(8, 8,  view.notes_input and 15 or  6)
  g:led(10, 8, view.sampling and 15 or 6)
  g:led(11, 8, view.patterns and 15 or 6)

  g:led(13, 8, MOD and glow or 6 )
  g:led(15, 8, ALT and glow  or 6 )
  g:led(16, 8, SHIFT and glow  or 6 )
  
  
  g:refresh()

end

