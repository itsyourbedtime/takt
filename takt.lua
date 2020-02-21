-- takt v2.2
-- @its_your_bedtime
--
-- parameter locking sequencer
--

local sampler = include('lib/sampler')
local browser = include('lib/browser')
local timber = include('lib/timber_takt')
local takt_utils = include('lib/_utils')
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
local freq_map = controlspec.WIDEFREQ
local amp_map = controlspec.DB
      amp_map.maxval = 16
local send_map = controlspec.new(-48, 0, 'db', 0, -48, "dB")--.DB
local sidechain_map = controlspec.new(-99, 0, 'db', 0, -99, "dB")--.DB
local threshold_map  = controlspec.new(0.01, 1, "exp", 0.001, 0.1, "")
local time_map = controlspec.new(0.0001, 5, 'exp', 0, 0.1, 's')

--
local g = grid.connect()
local data = { pattern = 1, ui_index = 1, selected = { 1, false },  metaseq = { from = 1, to = 1, div = 1}, [1] = takt_utils.make_default_pattern() }
local view = { steps_engine = true, steps_midi = false, notes_input = false, sampling = false, patterns = false } 
local choke = { 1, 2, 3, 4, 5, 6, 7, {},{},{},{},{},{},{}, ['8rt'] = {},['9rt'] = {},['10rt'] = {},['11rt'] = {}, ['12rt'] = {}, ['13rt'] = {},['14rt'] = {} }
local dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 2, [6] = 1.5, [7] = 1,} 
local midi_dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 1, [6] = 0.666, [7] = 0.545,} 
local sampling_actions = {[-1] = function()end,[0]=function()end, [1] = sampler.rec, [2] = sampler.play, [3] = sampler.save_and_load, [4] = sampler.clear, [5] = sampler.play, [6] = sampler.play }
local lfo_1, lfo_2 = {[5] = true, [13] = true,  }, {[6] = true, [14] = true,  }
local last_index = 1


local param_ids = { 
  ['quality'] = "quality", ['start_frame'] = "start_frame", ['end_frame'] = "end_frame", ['loop_start_frame'] = "loop_start_frame", ['loop_end_frame'] = "loop_end_frame", 
  ['freq_mod_lfo_1'] = "freq_mod_lfo_1", ['play_mode'] = 'play_mode', ['detune_cents'] = 'detune_cents',
  ['freq_mod_lfo_2'] = "freq_mod_lfo_2", ['filter_type'] = "filter_type", ['filter_freq'] = "filter_freq", ['filter_resonance'] = "filter_resonance", 
  ['filter_freq_mod_lfo_1'] = "filter_freq_mod_lfo_1", ['filter_freq_mod_lfo_2'] = "filter_freq_mod_lfo_2", ['pan'] = "pan", ['amp'] = "amp", 
  ['amp_mod_lfo_1'] = "amp_mod_lfo_1", ['amp_mod_lfo_2'] = "amp_mod_lfo_2", ['amp_env_attack'] = "amp_env_attack", ['amp_env_decay'] = "amp_env_decay", 
  ['amp_env_sustain'] = "amp_env_sustain", ['amp_env_release'] = "amp_env_release", ['reverb_send'] = "reverb_send", ["delay_send"] = 'delay_send', ['sidechain_send'] = 'sidechain_send'
  
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

local function to_id(x, y)
  return  x + ((y - 1) * 16) 
end

local function pattern_exists(x, y)
  return  data[x + ((y - 1) * 16)] ~= nil and true or false
end

local function id_to_x(id)
  return (id - 1) % 16 + 1
end

local function id_to_y(id)
  return math.ceil(id / 16)
end

local function K3_is_hold()
  return K3_hold
end

local function K1_is_hold()
  return K1_hold
end

local function set_enc_res(fine, coarse)
  return K3_is_hold() and coarse or fine  
end

local function reset_positions()
  for i = 1, 14 do
    data[data.pattern].track.pos[i] = 0
  end
end

local prev_mix_val = -1
local prev_level_val = 0

local function comp_shut(state)
    if state then
        print('run')
        params:set('comp_mix', prev_mix_val)
        params:set('comp_level', prev_level_val)
    elseif not state then 
        print('stop')
        prev_mix_val = params:get('comp_mix')
        prev_level_val = params:get('comp_level')
        params:set('comp_mix', -1)
        params:set('comp_level', -99)
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
  comp_shut(sequencer_metro.is_running)

  if string.find(pth, '.tkt') ~= nil then
    local saved = tab.load(pth)
    if saved ~= nil then
      print("data found")
      for k,v in pairs(saved[2]) do 
        data[k] = v
      end
      -- re-init metatables
      for t = 1, #data do 
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
  comp_shut(sequencer_metro.is_running)
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
  if not sampler.rec then
    for k, v in pairs(view) do
      view[k] = k == x and true or false
    end
  end
  if view.sampling or view.patterns then last_index = data.ui_index data.ui_index = 1  
  else
    data.ui_index = last_index
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
    move_params(tr, step, (s == t) and s or step) 
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

local function get_sample()
  return data[data.pattern][data.selected[1]].params[is_lock()].sample
end

local function sample_not_loaded(n)
  return params:get('sample_' .. n) == '-' 
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

local function get_sample_start(tr, s)
  local minval = params:lookup_param("start_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.minval
  data[data.pattern][tr].params[s].start_frame = minval
  data[data.pattern][tr].params[s].start_end_frame = minval
end
--- copy / settings

local function copy_step(src, dst)
    for i = 0, 15 do
      data[data.pattern][dst[1]][get_step(dst[2]) + i] = data[data.pattern][src[1]][get_step(src[2]) + i]
      data[data.pattern][dst[1]].params[get_step(dst[2]) + i] = deepcopy(data[data.pattern][src[1]].params[get_step(src[2]) + i])
    end
end

local function copy_pattern(src, dst)
    data[dst] = deepcopy(data[src])
end

local function open_sample_settings()
    local p = is_lock()
    norns.menu.toggle(true)
    norns.encoders.set_sens(2,1)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 36 +(( data[data.pattern][data.selected[1]].params[p].sample - 1 ) * 51 ))
    norns.encoders.set_sens(2,4)
end

 function open_settings(i)
     norns.menu.toggle(true)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 10 + (i*4))
end

local function change_filter_type()
    local tr = data.selected[1]
    local p = is_lock()
    p = type(p) == 'string' and p or get_step(p)
    data[data.pattern][tr].params[p].filter_type =  data[data.pattern][tr].params[p].filter_type
    data[data.pattern][tr].params[p].filter_type = (data[data.pattern][tr].params[p].filter_type % 2 ) + 1
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
local m_div = function(div) return  div == 1 and 2 or div^2 end

local function change_pattern(pt)
  if data[pt] == nil then
    data[pt] = takt_utils.make_default_pattern()
  end
    data.pattern = pt
end

local function metaseq(stage)
    if data[data.pattern].track.pos[1] == data[data.pattern].track.len[1] - 1 then
      
        if ptn_change_pending then
          change_pattern(ptn_change_pending)
          ptn_change_pending = false
        end
        
      if (data.metaseq.to and data.metaseq.from) then
          change_pattern(data.pattern < data.metaseq.to and data.pattern + 1 or data.metaseq.from)
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
      local pt = (util.clamp(data.pattern + d, 1, 64))
      change_pattern(pt)
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
[-1] = function(tr, s, d) -- sidechain
     data[data.pattern][tr].params[tostring(tr)].sidechain_send = util.clamp(data[data.pattern][tr].params[tostring(tr)].sidechain_send + d, -99, 0 )
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
      data[data.pattern][tr].params[s].sample = util.clamp(data[data.pattern][tr].params[s].sample + d, 1, 99)
  end, 
  [2] = function(tr, s, d) -- note
      if K3_is_hold() then 
        data[data.pattern][tr].params[s].detune_cents = util.clamp(data[data.pattern][tr].params[s].detune_cents + d, -100, 100)
      else
        data[data.pattern][tr].params[s].note = util.clamp(data[data.pattern][tr].params[s].note + d, 25, 127)
      end
  end,
  [3] = function(tr, s, d) -- start
      local sample = data[data.pattern][tr].params[s].sample
      local pspec = params:lookup_param("start_frame_" .. sample).controlspec
      local start = util.clamp(pspec:unmap( data[data.pattern][tr].params[s].start_frame ) + (d / set_enc_res(200, 1000) ), 0, 1)
      data[data.pattern][tr].params[s].start_frame = pspec:map(start) 
      data[data.pattern][tr].params[s].lool_start_frame = pspec:map(start)
  end,
  [4] = function(tr, s, d) -- len
      local sample = data[data.pattern][tr].params[s].sample
      local pspec = params:lookup_param("end_frame_" .. sample).controlspec
      local length = util.clamp(pspec:unmap( data[data.pattern][tr].params[s].end_frame ) + (d / set_enc_res(200, 1000)), 0, 1)
      data[data.pattern][tr].params[s].end_frame = pspec:map(length)  
      data[data.pattern][tr].params[s].loop_end_frame = pspec:map(length)
   end,
  [5] = function(tr, s, d) -- freq mod lfo 1 freq_lfo1
        --[[          local pspec = params:lookup_param("lfo_1_freq").controlspec
                  local freq = util.clamp(pspec:unmap( params:get('lfo_1_freq') ) + (d / 10), 0, 1)
                  params:set('lfo_1_freq', pspec:map(freq))
        ]]
      data[data.pattern][tr].params[s].freq_mod_lfo_1 = util.clamp(data[data.pattern][tr].params[s].freq_mod_lfo_1 + d / 100, 0, 1)
  end,
  [6] = function(tr, s, d) -- freq mod lfo 2
        data[data.pattern][tr].params[s].freq_mod_lfo_2 = util.clamp(data[data.pattern][tr].params[s].freq_mod_lfo_2 + d / 100, 0, 1)
  end,
  [7] = function(tr, s, d) -- volume
        data[data.pattern][tr].params[s].amp = amp_map:map(util.clamp(amp_map:unmap(data[data.pattern][tr].params[s].amp) + d / 200, 0,1 ))
  end,
  [8] = function(tr, s, d) -- pan
        data[data.pattern][tr].params[s].pan = util.clamp(data[data.pattern][tr].params[s].pan + d / 20 , -1, 1)
  end,
  [9] = function(tr, s, d) -- atk
    data[data.pattern][tr].params[s].amp_env_attack = util.clamp(data[data.pattern][tr].params[s].amp_env_attack + d / 50, 0, 5)
  end,
  [10] = function(tr, s, d) -- dec
      data[data.pattern][tr].params[s].amp_env_decay = util.clamp(data[data.pattern][tr].params[s].amp_env_decay + d / 50, 0.01, 5)
  end,
  [11] = function(tr, s, d) -- sus
      data[data.pattern][tr].params[s].amp_env_sustain = util.clamp(data[data.pattern][tr].params[s].amp_env_sustain + d / 50, 0, 1)
  end,
  [12] = function(tr, s, d) -- rel
      data[data.pattern][tr].params[s].amp_env_release = util.clamp(data[data.pattern][tr].params[s].amp_env_release + d / 10, 0, 10)
  end,
  [13] = function(tr, s, d)
        data[data.pattern][tr].params[s].amp_mod_lfo_1 = util.clamp(data[data.pattern][tr].params[s].amp_mod_lfo_1 + d / 100, 0, 1)
  end,
  [14] = function(tr, s, d) 
        data[data.pattern][tr].params[s].filter_freq_mod_lfo_2 = util.clamp(data[data.pattern][tr].params[s].filter_freq_mod_lfo_2 + d / 100, 0, 1)
  end,
  [15] = function(tr, s, d) 
      data[data.pattern][tr].params[s].quality = util.clamp(data[data.pattern][tr].params[s].quality + d, 1, 5)
  end,
  [16] = function(tr, s, d) 
      data[data.pattern][tr].params[s].play_mode = util.clamp(data[data.pattern][tr].params[s].play_mode + d, 1, 4)
  end,
  [17] = function(tr, s, d) 
      local fr = freq_map:unmap(data[data.pattern][tr].params[s].filter_freq)
      fr = util.clamp(fr + d / 200,0.1,1)
      data[data.pattern][tr].params[s].filter_freq = freq_map:map(fr)
  end,
  [18] = function(tr, s, d) 
      data[data.pattern][tr].params[s].filter_resonance = util.clamp(data[data.pattern][tr].params[s].filter_resonance + d / 20, 0, 1)
  end,
  [19] = function(tr, s, d)
        data[data.pattern][tr].params[s].delay_send = send_map:map(util.clamp(send_map:unmap(data[data.pattern][tr].params[s].delay_send) + d / 200, 0,1 ))
  end,
  [20] = function(tr, s, d) 
        data[data.pattern][tr].params[s].reverb_send = send_map:map(util.clamp(send_map:unmap(data[data.pattern][tr].params[s].reverb_send) + d / 200, 0,1 ))  end,
  
}

local sampling_params = {
  [-1] = function(d)sampler.mode = util.clamp(sampler.mode + d, 1, 4) sampler.set_mode() end,
  [0] = function(d) sampler.source = util.clamp(sampler.source + d, 1, 2) sampler.set_source() end,
  [3] = function(d) sampler.slot = util.clamp(sampler.slot + d, 1, 100) end,
  [5] = function(d) sampler.start = util.clamp(sampler.start + d / (20), 0, sampler.length) sampler.set_start(sampler.start) end,
  [6] = function(d) sampler.length = util.clamp(sampler.length + d / (20), sampler.start, sampler.rec_length) end,
  [4] = function(d) end, --play
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
        comp_shut(sequencer_metro.is_running)
      end
    end,
  [3] = function(z)  if view.notes_input and z == 1 and sequencer_metro.is_running then PATTERN_REC = not PATTERN_REC end end,
  [5] = function(z)  if z == 1 then if not view.notes_input then set_view('steps_engine') PATTERN_REC = false end tr_change(1)  end end,
  [6] = function(z)  if z == 1 then  if not view.notes_input then set_view('steps_midi') PATTERN_REC = false end tr_change(8)  end end,
  [8] = function(z)  if z == 1 then set_view(view.notes_input and (data.selected[1] < 8 and 'steps_engine' or 'steps_midi') or 'notes_input') end end,
  [10] = function(z) if z == 1 then set_view(view.sampling and (data.selected[1] < 8 and 'steps_engine' or 'steps_midi') or 'sampling') end  end,
  [11] = function(z) if z == 1 then set_view(view.patterns and (data.selected[1] < 8 and 'steps_engine' or 'steps_midi') or 'patterns') end end,
  [13] = function(z) MOD = z == 1 and true or false if z == 0 then copy = { false, false } end end,
  [15] = function(z) ALT = z == 1 and true or false end,
  [16] = function(z) SHIFT = z == 1 and true or false end,
}

local params_fx = {
  [1] = function(d) params:set('comp_level', params:get('comp_level') + d) end,
  [2] = function(d) params:set('comp_mix', params:get('comp_mix') + d / 50) end,
  [3] = function(d)
    local val = threshold_map:unmap(params:get('comp_threshold'))
    params:set('comp_threshold', threshold_map:map(util.clamp(val + d /200, 0.001, 1 ))) 
  end, 
  [4] = function(d) params:set('comp_slopebelow', params:get('comp_slopebelow') + d / 100) end,
  [5] = function(d) params:set('comp_slopeabove', params:get('comp_slopeabove') + d / 100) end,
  [6] = function(d) params:set('comp_clamptime', params:get('comp_clamptime') + d / 100)  end,
  [7] = function(d) params:set('comp_relaxtime', params:get('comp_relaxtime') + d / 100) end,
  [8] = function(d) params:set('reverb_time', params:get('reverb_time') + d / 5) end,
  [9] = function(d) params:set('reverb_size', params:get('reverb_size') + d / 50) end,
  [10] = function(d) params:set('reverb_damp', params:get('reverb_damp') + d / 100) end,
  [11] = function(d) params:set('reverb_diff', params:get('reverb_diff') + d / 100) end,
  [12] = function(d) params:set('delay_level', params:get('delay_level') + d) end,
  [13] = function(d) 
    local val = time_map:unmap(params:get('delay_time'))
    params:set('delay_time', time_map:map(util.clamp(val + d /100, 0.001, 1 ))) 
  end,
  [14] = function(d) params:set('delay_feedback', params:get('delay_feedback') + d / 50) end,
  [15] = function(d) params:set('lfo_1_freq', params:get('lfo_1_freq') + d / 10) end,
  [16] = function(d) params:set('lfo_1_wave_shape', params:get('lfo_1_wave_shape') + d) end,
  [17] = function(d) params:set('lfo_2_freq', params:get('lfo_2_freq') + d / 10) end,
  [18] = function(d) params:set('lfo_2_wave_shape', params:get('lfo_2_wave_shape') + d) end,
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

      
    for i = 1, 14 do
      hold[i] = 0
      holdmax[i] = 0
      first[i] = 0
      second[i] = 0
    end
    hold['p'] = 0
    
    redraw_params[1] = data[1][1].params[tostring(1)]
    redraw_params[2] = data[1][1].params[tostring(1)]

    timber.init()
    sampler.init()
    ui.init()

    sequencer_metro = metro.init()
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2) / 16 --[[ppqn]] / 4 
    sequencer_metro.event = function(stage) seqrun(stage) if stage % m_div(data.metaseq.div) == 0 then metaseq(stage) end end

    redraw_metro = metro.init(function(stage) redraw(stage) g:redraw() blink = (blink + 1) % 17 end, 1/30)
    redraw_metro:start()
    midi_clock = beatclock:new()
    midi_clock.on_step = function() end
    midi_clock:bpm_change( util.round(data[data.pattern].bpm / midi_dividers[util.clamp(data[data.pattern].sync_div, 1, 7)]))
    midi_clock.send = false
end

function enc(n,d)
  norns.encoders.set_sens(1,3)
  norns.encoders.set_sens(2,4)
  norns.encoders.set_sens(3,3)
  norns.encoders.set_accel(1, false)
  norns.encoders.set_accel(2, false)
  norns.encoders.set_accel(3, true)

  local tr = data.selected[1]
  local s = data.selected[2] and data.selected[2] or tostring(tr)
  if browser.open then
    browser.enc(n, d)
  elseif n == 1 then
      
      local offset = data.selected[1] > 7 and 7 or 0
      data.selected[1] = util.clamp(data.selected[1] + d, 1 + offset, 7 + offset)
      tr_change(data.selected[1])
      
  elseif n == 2 then
    
    if not view.sampling then
      if not K1_is_hold() then 
        data.ui_index = util.clamp(data.ui_index + d, not data.selected[2] and 1 or -3, (view.steps_midi or view.patterns) and 18 or 20)
      else
        data.ui_index = util.clamp(data.ui_index + d, view.patterns and -1 or -6, -1)
      end
    else
      if not sampler.rec then
        data.ui_index = util.clamp(data.ui_index + d, -1, 6)      
      end
    end
  elseif n == 3 then
    if view.patterns then 
      if K1_is_hold() then
        track_params[-1](tr, p, d)
      else
        params_fx[data.ui_index](d)
      end
    elseif not view.sampling then
      
      local p = is_lock()
      local t = type(p) == 'number' and get_step(p) or p

      data[data.pattern][tr].params[t].lock = data.selected[2] and 1 or 0
      
      redraw_params[1] = get_params(tr, is_lock())
      redraw_params[2] = redraw_params[1] 

      if K1_is_hold() then
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
  K1_hold = (n == 1 and z == 1) and true or false
  K3_hold = (n == 1 and z == 1) and true or false
  if browser.open then
    browser.key(n, z)

  elseif n == 1 then
    if K1_is_hold() and not view.sampling and not view.patterns then 
      data.ui_index = -4 
    elseif K1_is_hold() and view.patterns then
      data.ui_index = -1 
    else 
      data.ui_index = 1 
    end
  elseif n == 2 and z == 1 then
    if view.patterns then
      set_view(view.notes_input and (data.selected[1] < 8 and 'steps_engine' or 'steps_midi'))
    elseif browser.open then
      
      browser.exit()
    end
  elseif n == 3 then
    if view.sampling then
        sampling_actions[data.ui_index](z)
        if z == 1 and ((data.ui_index == 1 and sampler.rec) or data.ui_index == 4) then ui.waveform = {} end
    elseif view.patterns then 
        --open_settings(2)
        --open_settings(3.5)
        --open_settings(5.5)
      elseif not view.steps_midi then
      if data.ui_index == 1 and z == 1  then 
          local sample_id = data[data.pattern][data.selected[1]].params[is_lock()].sample
          browser.enter(_path.audio, timber.load_sample, sample_id)
      elseif (data.ui_index == 3 or data.ui_index == 4) and z == 1 and sample_not_loaded(get_sample()) then
          local sample_id = data[data.pattern][data.selected[1]].params[is_lock()].sample
          browser.enter(_path.audio, timber.load_sample, sample_id)
      elseif (data.ui_index == 17 or data.ui_index == 18) and z == 1 then
          change_filter_type()
      elseif lfo_1[data.ui_index] then
          set_view('patterns')
          data.ui_index = 15
      elseif lfo_2[data.ui_index] then
          set_view('patterns')
          data.ui_index = 17
      elseif data.ui_index == 19 then
          set_view('patterns')
          data.ui_index = 12
      elseif data.ui_index == 20 then
          set_view('patterns')
          data.ui_index = 8
      end
    end
  end
end

function redraw(stage)

  local tr = data.selected[1]
  local pos = data[data.pattern].track.pos[tr]
  local params_data = get_params(tr, sequencer_metro.is_running and pos or false, true)
  
  
  
  if data.selected[2] then
    redraw_params[1] = get_params(data.selected[1], get_step(data.selected[2]), true)
  elseif not data.selected[2] then
    redraw_params[1] = redraw_params[2]
  end
  
  screen.clear()

  ui.head(redraw_params[1], data, view, K1_is_hold(), rules, PATTERN_REC, browser.preview)
  
  if view.sampling then 
    local pos = sampler.get_pos()
    ui.sampling(sampler, data.ui_index, pos)
  elseif view.patterns then 
    ui.patterns(data.pattern, data.metaseq, data.ui_index, stage)
  else
    if data.selected[1] < 8 then
      local meta = timber.get_meta(redraw_params[1].sample)
      -- length hack
      local max_len = meta.num_frames
      if params_data.end_frame == 2000000000 and meta.waveform[2] ~= nil then
        get_sample_len(tr, is_lock())
      elseif params_data.end_frame > max_len then
        get_sample_len(tr, is_lock())
      elseif params_data.start_frame > max_len then
        get_sample_start(tr, is_lock())
      end
      ui.main_screen(redraw_params[1], data.ui_index, meta, browser)
      if browser.open then browser.redraw() end
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
    hold['p'] = hold['p'] + (z * 2 - 1)
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
      local id = to_id(x,y)
      if y < 5 and z == 1 then
        if SHIFT then
          if data.pattern ~= id then
            data[id] = nil
          end
        elseif MOD then 
            if not ptn_copy then 
              ptn_copy = id
            else
              copy_pattern(ptn_copy, id)
            end
        else
          if hold['p'] == 1 then
            first['p'] = id
            if ptn_change_pending then
                change_pattern(ptn_change_pending)
                ptn_change_pending = false
            else
                ptn_change_pending = id
            end
            data.metaseq.from = false
            data.metaseq.to = false
            ptn_copy = false
          elseif hold['p'] == 2 then
            second['p'] = id
            data.metaseq.from = first['p']
            data.metaseq.to = second['p']
          end
        end
      elseif y == 6 then
        data.metaseq.div = x 
      end
    end
  else
    if controls[x] then
      controls[x](z)
    end
    if z == 1 then
      if view.sampling or view.patterns then
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
        if y < 5 then 
            local id = to_id(x,y)
            --print(id)
            local level =
            id == ptn_change_pending  and sequencer_metro.is_running and  util.clamp(blink, 5, 14)
            or (data.metaseq.from and data.metaseq.to) and id == data.pattern and  util.clamp(blink, 5, 14)
            or (id >= (data.metaseq.from and data.metaseq.from or data.pattern) and id <= (data.metaseq.to and data.metaseq.to or data.pattern)) and 9 
            or data.pattern == id and 15 
            or pattern_exists(x, y) and 6
            or 2
            g:led(x, y, level)
        elseif y == 6 then
          g:led(x, y, x == data.metaseq.div and 15 or 2)
        end
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

