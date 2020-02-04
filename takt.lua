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
local midi_clock
local hold_time = 0
local down_time = 0
local midi_in_device
--
local midi_in_device
local REC_CC = 38
--
local blink = 1
local ALT, SHIFT, MOD, PATTERN_REC = false, false, false, false
local hold, holdmax, first, second = {}, {}, {}, {}
local copy = { false, false }
local ptn_copy = false
local redraw_params = {}
local g = grid.connect()

local data = {
  pattern = 1,
  ui_index = 1,
  selected = { 1, false }, 
  settings = {},
  in_l = 0,
  in_r = 0,
  sampling = {
    source = 1,
    mode = 1,
    play = false,
    rec = false,
    start = 0,
    length = 60,
    slot = 1, 
  },
  metaseq = { from = 1, to = 1 },

}


local view = { steps_engine = true, notes_input = false, sampling = false, patterns = false } 

local choke = { 1, 2, 3, 4, 5, 6, 7 }

local dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 2, [6] = 1.5, [7] = 1,} 

local param_ids = {
      ['sr'] = "quality", ['start'] = "start_frame", ['s_end'] = "end_frame", ['l_start'] = "loop_start_frame", ['l_end'] = "loop_end_frame", ['freq_lfo1'] = "freq_mod_lfo_1", ['mode'] = 'play_mode',
      ['freq_lfo2'] = "freq_mod_lfo_2", ['ftype'] = "filter_type", ['cutoff'] = "filter_freq", ['resonance'] = "filter_resonance", 
      ['cut_lfo1'] = "filter_freq_mod_lfo_1", ['cut_lfo2'] = "filter_freq_mod_lfo_2", ['pan'] = "pan", ['vol'] = "amp", 
      ['amp_lfo1'] = "amp_mod_lfo_1", ['amp_lfo2'] = "amp_mod_lfo_2", ['attack'] = "amp_env_attack", ['decay'] = "amp_env_decay", 
      ['sustain'] = "amp_env_sustain", ['release'] = "amp_env_release",
}

local rule = {
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
    data[data.pattern][tr].params[step].note = math.random(20,120) return true end },
  [16] = {'+- NOTE', function(tr, step) 
    data[data.pattern][tr].params[step].note = data[data.pattern][tr].params[step].note + math.random(-10,10) return true end },
  [17] = {'RND START', function(tr, step) 
    data[data.pattern][tr].params[step].start = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval) 
    return true end },
  [18] = {'RND ST-EN', function(tr, step) 
    data[data.pattern][tr].params[step].start = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval)
    data[data.pattern][tr].params[step].s_end = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval)
    return true end },
}


local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function reset_positions()
  for i = 1, 7 do
    data[data.pattern].track.pos[i] = 0
  end
end


local function set_bpm(n)
    data[data.pattern].bpm = n
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2)  / 16 --[[ppqn]] / 4 
    midi_clock:bpm_change(data[data.pattern].bpm * dividers[data[data.pattern].sync_div])
end

local function load_project(pth)
  
  sequencer_metro:stop() 
  midi_clock:stop()
  engine.noteOffAll()
  
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
      end
      
      
      if saved[1] then params:read(norns.state.data .. saved[1] .. ".pset") end
      reset_positions()
    else
      print("no data")
    end
  end
end

local function save_project(txt)
  sequencer_metro:stop() 
  midi_clock:stop()
  engine.noteOffAll()
  if txt then
    tab.save({ txt, data }, norns.state.data .. txt ..".tkt")
    params:write( norns.state.data .. txt .. ".pset")
  else
    print("save cancel")
  end
end

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

local function set_view(x)
    data.ui_index = 1 
    for k, v in pairs(view) do
      view[k] = k == x and true or false
    end
end

local function sync_tracks(tr)
    for i=1, 7 do
      --if data[data.pattern].track.div[i] == data[data.pattern].track.div[tr] then
        data[data.pattern].track.pos[i] = data[data.pattern].track.pos[tr]
      --end
    end
end

local function set_loop(tr, start, len)
    data[data.pattern].track.start[tr] = get_step(start)
    data[data.pattern].track.len[tr] = get_step(len) + 15
    sync_tracks(tr)
end

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

local function tr_change(tr)
  redraw_params[1] = get_params(tr)
  redraw_params[2] = redraw_params[1]
end

local function is_lock()
    local src = data.selected
    if src[2] == false then
      return tostring(src[1])
    else
      return src[2]
    end
end

local function open_sample_settings()
    local p = is_lock()
    norns.menu.toggle(true)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 25 +(( data[data.pattern][data.selected[1]].params[p].sample - 1 ) * 94 ))
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


local function set_locks(step_param)
    for k, v in pairs(step_param) do
      if param_ids[k] ~= nil then
        params:set(param_ids[k]  .. '_' .. step_param.sample, v)
      end
    end
end

local function metaseq(counter)
    if data[data.pattern].track.pos[1] == data[data.pattern].track.len[1] - 1 then
      data.pattern = data.pattern < data.metaseq.to and data.pattern + 1 or data.metaseq.from
      set_bpm(data[data.pattern].bpm)
    end
end


local function seqrun(counter)
  --if prev == nil then prev = get_params(1) end

  for tr = 1, 7 do

      local start = data[data.pattern].track.start[tr]
      local len = data[data.pattern].track.len[tr]
      local div = data[data.pattern].track.div[tr]
      
      if (div ~= 6 and counter % dividers[div] == 0) 
      or (div == 6 and counter % dividers[div] >= 0.5) then

        data[data.pattern].track.pos[tr] = util.clamp((data[data.pattern].track.pos[tr] + 1) % (len ), start, len) -- voice pos
        data[data.pattern].track.cycle[tr] = counter % 256 == 0 and data[data.pattern].track.cycle[tr] + 1 or data[data.pattern].track.cycle[tr]  --data[data.pattern].track.cycle[tr]

        local mute = data[data.pattern].track.mute[tr]
        local pos = data[data.pattern].track.pos[tr]
        local trig = data[data.pattern][tr][pos]
        
        
        if trig == 1 and not mute then
          

          set_locks(data[data.pattern][tr].params[tostring(tr)])
          
          local step_param = get_params(tr, pos)
          
          data[data.pattern].track.div[tr] = step_param.div ~= data[data.pattern].track.div[tr] and step_param.div or data[data.pattern].track.div[tr]

          if rule[step_param.rule][2](tr, pos) then 
            step_param = step_param.lock ~= 1 and get_params(tr) or step_param
            if tr == data.selected[1] then 
              redraw_params[1] = step_param
              redraw_params[2] = step_param
            end
            set_locks(step_param)
            choke_group(tr, step_param.sample)
            engine.noteOn(tr, music.note_num_to_freq(step_param.note), 1, step_param.sample)
            choke[tr] = step_param.sample
          end
       end
    end
  end
  
end

local function clear_substeps(tr, s )
  for l = s, s + 15 do
    data[data.pattern][tr][l] = 0
    data[data.pattern][tr].params[l] = {}
    setmetatable(data[data.pattern][tr].params[l], {__index =  data[data.pattern][tr].params[tostring(tr)]})
  end
end
local function move_params(tr, src, dst )
    local s = data[data.pattern][tr].params[src]
     data[data.pattern][tr].params[dst] = s
     --data[data.pattern][tr].params[src], data[data.pattern][tr].params[dst] = data[data.pattern][tr].params[dst], data[data.pattern][tr].params[src]
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

local function get_tr_start( tr )
  return math.ceil(data[data.pattern].track.start[tr] / 16)
end

local function get_tr_len( tr )
  return math.ceil(data[data.pattern].track.len[tr] / 16)
end

local function place_note(tr, step, note)
  data[data.pattern][tr][step] = 1
  data[data.pattern][tr].params[step].lock = 1
  data[data.pattern][tr].params[step].note = data[data.pattern][tr].params[step].note
  data[data.pattern][tr].params[step].note = note
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

function init()
  
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
    
  math.randomseed(os.time())

    params:add_trigger('save_p', "< Save project" )
    params:set_action('save_p', function(x) textentry.enter(save_project,  'new') end)
    params:add_trigger('load_p', "> Load project" )
    params:set_action('load_p', function(x) fileselect.enter(norns.state.data, load_project) end)
    params:add_trigger('new', "+ New" )
    params:set_action('new', function(x) init() end)
    params:add_separator()


  
  local vu_l, vu_r = poll.set("amp_in_l"), poll.set("amp_in_r")
  vu_l.time, vu_r.time = 1 / 30, 1 / 30
  
  vu_l.callback = function(val) data.in_l = util.clamp(val * 180, 1, 70) end
  vu_r.callback = function(val) data.in_r = util.clamp(val * 180, 1, 70) end
  vu_l:start()
  vu_r:start()

    for i = 1, 7 do
      hold[i] = 0
      holdmax[i] = 0
      first[i] = 0
      second[i] = 0
    end

    for t = 1, 16 do
      data[t] = {
        bpm = 120,
        sync_div = 5,
        track = {
            mute = { false, false, false, false, false, false, false },
            pos = { 0, 0, 0, 0, 0, 0, 0 },
            start =  { 1, 1, 1, 1, 1, 1, 1 },
            len = { 256, 256, 256, 256, 256, 256, 256 },
            div = { 5, 5, 5, 5, 5, 5, 5 },
            cycle = {1, 1, 1, 1, 1, 1, 1 },
          },
    }

      for l = 1, 7 do
  
        data[t][l] = {}
        data[t][l].params = {}
        data[t][l].params[tostring(l)] = {
            offset = 0,
            sample = l,
            note = 60,
            retrig = 0,
            mode = 3,
            start = 0,
            l_start = 0,
            s_end = 99999999,
            l_end = 99999999,
            vol = 0,
            pan = 0,
            attack = 0,
            decay = 1,
            sustain = 1,
            release = 0,
            ftype = 1,
            cutoff = 20000,
            resonance = 0,
            sr = 5,
            freq_lfo1 = 0,
            freq_lfo2 = 0,
            amp_lfo1 = 0,
            amp_lfo2 = 0,
            cut_lfo1 = 0,
            cut_lfo2 = 0,
            lock = 0,
            rule = 0,
            retrig = 0,
            div = 5,
        }
    
        for i=0,256 do
          data[t][l][i] = 0
          data[t][l].params[i] = {}
          setmetatable(data[t][l].params[i], {__index =  data[t][l].params[tostring(l)]})
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
    midi_clock.send = true

    engines.init()
    ui.init()
end

local sampling_params = {
  [-1] = function(d)engines.sc.mode = util.clamp(engines.sc.mode + d, 1, 4) engines.set_mode(engines.sc.mode) end,
  [0] = function(d) engines.sc.source = util.clamp(engines.sc.source + d, 1, 2) engines.set_source(engines.sc.source) end,
  [5] = function(d) engines.sc.slot = util.clamp(engines.sc.slot + d, 1, 100) end,
  [3] = function(d) engines.sc.start = util.clamp(engines.sc.start + d / 10, 0, 15) engines.set_start(engines.sc.start) end,
  [4] = function(d) engines.sc.length = util.clamp(engines.sc.length + d / 10, engines.sc.start, 15) end,--engines.set_length(engines.sc.length) end,
  [6] = function(d) end, --play
  [1] = function(d) end, --save
  [2] = function(d) end, --clear
  [7] = function(d) end, --clear

}

local function get_len(tr, s)
  local maxval = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.maxval
  data[data.pattern][tr].params[s].s_end = maxval
  data[data.pattern][tr].params[s].l_end = maxval
end

local track_params = {
  [-6] = function(tr, s, d) -- ptn
      data.pattern = (util.clamp(data.pattern + d, 1, 16))
      data.metaseq.from = data.pattern
      data.metaseq.to = data.pattern
  end,
  [-5] = function(tr, s, d) -- rnd
      data.selected[1] = util.clamp(data.selected[1] + d, 1, 7)
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
      data[data.pattern].sync_div = util.clamp(data[data.pattern].sync_div + d, 1, 7)
  end,
  [-1] = function(tr, s, d) -- 

  end,  
}

local step_params = {
  [-3] = function(tr, s, d) -- 
    data[data.pattern][tr].params[s].div = util.clamp(data[data.pattern][tr].params[s].div + d, 1, 7)
  end,
  [-2] = function(tr, s, d) -- rule
      data[data.pattern][tr].params[s].rule = util.clamp(data[data.pattern][tr].params[s].rule + d, 0, #rule)
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
  [1] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].sample = util.clamp(data[data.pattern][tr].params[s].sample + d, 1, 100)
  end, 
  [2] = function(tr, s, d) -- note
      data[data.pattern][tr].params[s].note = util.clamp(data[data.pattern][tr].params[s].note + d, 25, 127)
      --
  end,
  [3] = function(tr, s, d) -- start
      local sample = data[data.pattern][tr].params[s].sample
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval 
      data[data.pattern][tr].params[s].start = util.clamp(data[data.pattern][tr].params[s].start + ((d) * (length / 1000)), 0,  length)
      data[data.pattern][tr].params[s].l_start = data[data.pattern][tr].params[s].start
  end,
  [4] = function(tr, s, d) -- len
      local sample = data[data.pattern][tr].params[s].sample
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval
      
      data[data.pattern][tr].params[s].s_end = util.clamp(data[data.pattern][tr].params[s].s_end + ((d) * (length / 1000)), 0, length)
      data[data.pattern][tr].params[s].l_end = data[data.pattern][tr].params[s].s_end
   end,
  [5] = function(tr, s, d) -- freq mod lfo 1 freq_lfo1
        data[data.pattern][tr].params[s].freq_lfo1 = util.clamp(data[data.pattern][tr].params[s].freq_lfo1 + d / 100, 0, 1)
  end,
  [6] = function(tr, s, d) -- freq mod lfo 2
        data[data.pattern][tr].params[s].freq_lfo2 = util.clamp(data[data.pattern][tr].params[s].freq_lfo2 + d / 100, 0, 1)

  end,
  [7] = function(tr, s, d) -- volume
        data[data.pattern][tr].params[s].vol = util.clamp(data[data.pattern][tr].params[s].vol + d / 10  , -48, 16)
  end,
  [8] = function(tr, s, d) -- pan
        data[data.pattern][tr].params[s].pan = util.clamp(data[data.pattern][tr].params[s].pan + d / 10 , -1, 1)
  end,
  [9] = function(tr, s, d) -- atk
    data[data.pattern][tr].params[s].attack = util.clamp(data[data.pattern][tr].params[s].attack + d / 10, 0, 5)
  end,
  [10] = function(tr, s, d) -- dec
      data[data.pattern][tr].params[s].decay = util.clamp(data[data.pattern][tr].params[s].decay + d / 10, 0, 5)
  end,
  [11] = function(tr, s, d) -- sus
      data[data.pattern][tr].params[s].sustain = util.clamp(data[data.pattern][tr].params[s].sustain + d / 10, 0, 1)
  end,
  [12] = function(tr, s, d) -- rel
      data[data.pattern][tr].params[s].release = util.clamp(data[data.pattern][tr].params[s].release + d / 10, 0, 10)
  end,
  [13] = function(tr, s, d) -- amp mod lfo 1
        data[data.pattern][tr].params[s].amp_lfo1 = util.clamp(data[data.pattern][tr].params[s].amp_lfo1 + d / 100, 0, 1)

  end,
  [14] = function(tr, s, d) -- amp mod lfo 2
        data[data.pattern][tr].params[s].amp_lfo2 = util.clamp(data[data.pattern][tr].params[s].amp_lfo2 + d / 100, 0, 1)

  end,
  [15] = function(tr, s, d) -- sample rate
      data[data.pattern][tr].params[s].sr = util.clamp(data[data.pattern][tr].params[s].sr + d, 1, 5)
  end,
  [16] = function(tr, s, d) -- mode
      data[data.pattern][tr].params[s].mode = util.clamp(data[data.pattern][tr].params[s].mode + d, 1, 4)
  end,
  [17] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].cutoff = util.clamp(data[data.pattern][tr].params[s].cutoff + (d * 200), 0, 20000)
  end,
  [18] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].resonance = util.clamp(data[data.pattern][tr].params[s].resonance + d / 10, 0, 1)
  end,
  [19] = function(tr, s, d) -- filter cutoff mod lfo 1
        data[data.pattern][tr].params[s].cut_lfo1 = util.clamp(data[data.pattern][tr].params[s].cut_lfo1 + d / 100, 0, 1)

  end,
  [20] = function(tr, s, d) -- filter cutoff mod lfo 2
        data[data.pattern][tr].params[s].cut_lfo2 = util.clamp(data[data.pattern][tr].params[s].cut_lfo2 + d / 100, 0, 1)

  end,
  
}


function enc(n,d)
  norns.encoders.set_sens(1,4)
  norns.encoders.set_sens(2,4)
  norns.encoders.set_sens(3,4)
  norns.encoders.set_accel(1, false)
  norns.encoders.set_accel(2, false)
  norns.encoders.set_accel(3, ((data.ui_index == 3 or data.ui_index == 4) and view.steps_engine) and true or false)

  local tr = data.selected[1]
  local s = data.selected[2] and data.selected[2] or tostring(data.selected[1])
  
  if n == 1 then
        data.selected[1] = util.clamp(data.selected[1] + d, 1, 7)
        tr_change(data.selected[1])
  elseif n == 2 then
    
    if not view.sampling then
      if not K1_hold then 
        data.ui_index = util.clamp(data.ui_index + d, not data.selected[2] and 1 or -3, 20)
      else
        data.ui_index = util.clamp(data.ui_index + d, -6, -1)
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
      if K1_hold then
        track_params[data.ui_index](tr, p, d)
      else
        
        redraw_params[1] = get_params(tr, is_lock())
        redraw_params[2] = redraw_params[1] 
        
        if type(p) == 'string' then
          step_params[data.ui_index](tr, p, d)
        else
          if data.ui_index > 0 then
            for i = t, t + 15 do step_params[data.ui_index](tr, i, d) end
          else
            step_params[data.ui_index](tr, t, d)
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
  if n == 1 then 
    K1_hold = z == 1 and true or false
    if z == 1 and not view.sampling then 
      data.ui_index = -4
    elseif z == 0 and not view.sampling then  
      data.ui_index = 1
    end
  end

  if n == 2 and z == 1 then

  elseif n == 3 then
    if view.sampling then
      if data.ui_index == 1 and z == 1  then
          engines.rec()

      elseif data.ui_index == 2 or data.ui_index == 3 or data.ui_index == 4 then
          engines.play(z == 1 and true or false)
        
      elseif data.ui_index == 5 and z == 1  then
          engines.save_and_load(data.sampling.slot)
          params:set('play_mode_' .. data.sampling.slot, 2)
      elseif data.ui_index == 6  and z == 1 then
          engines.clear()
          ui.waveform = {}
      end
    else
      if data.ui_index == 1 and z == 1 then
        open_sample_settings()
      elseif (data.ui_index == 17 or data.ui_index == 18) and z == 1 then
        change_filter_type()
        
        
      end
    end
  end
end


function redraw()

  local tr = data.selected[1]
  local pos = data[data.pattern].track.pos[tr]
  local trig = data[data.pattern][tr][pos]
  local params_data = get_params(tr, sequencer_metro.is_running and pos or false, true)

  
  if data.selected[2] then
    redraw_params[1] = get_params(data.selected[1], get_step(data.selected[2]), true)
  elseif not data.selected[2] then
    redraw_params[1] = redraw_params[2]
  end
  

  -- length hack
  if params_data.s_end == 99999999 and engines.get_meta(params_data.sample).waveform[2] ~= nil then
    get_len(tr, is_lock())
  end

  screen.clear()
  
  ui.head(redraw_params[1], data, view, K1_hold, rule, PATTERN_REC)
  
  if view.sampling then 
    local pos = engines.get_pos()
    local len = engines.get_len()
    local state = engines.get_state()
    --print(pos)
    ui.sampling(engines.sc, data.ui_index, data.in_l, data.in_r, pos)--, len, state) 
  else
    local meta = engines.get_meta(params_data.sample)
    ui.main_screen(redraw_params[1], data.ui_index, meta)
  end
  
  screen.update()

end

local controls = {
  [1] = function(z) -- start / stop, 
      if z == 1 then
        if sequencer_metro.is_running then 
          sequencer_metro:stop() 
          midi_clock:stop()
          if MOD then engine.noteOffAll() end
        else 
          sequencer_metro:start() 
          midi_clock:start()
        end
        if MOD then
          reset_positions()
        end
      end
    end,
  [3] = function(z)  if view.notes_input and z == 1 and sequencer_metro.is_running then PATTERN_REC = not PATTERN_REC end end,
  [8] = function(z)  if z == 1 then set_view('steps_engine') PATTERN_REC = false end end,
  [9] = function(z)  if z == 1 then set_view(view.notes_input and 'steps_engine' or 'notes_input') end end,
  [10] = function(z) if z == 1 then set_view(view.sampling and 'steps_engine' or 'sampling') end  end,
  [11] = function(z) if z == 1 then set_view(view.patterns and 'steps_engine' or 'patterns') end end,
  [13] = function(z) MOD = z == 1 and true or false if z == 0 then copy = { false, false } end end,
  [15] = function(z) ALT = z == 1 and true or false end,
  [16] = function(z) SHIFT = z == 1 and true or false end,
}

function g.key(x, y, z)
  screen.ping()
  
      if view.notes_input then
      
        local note = linn.grid_key(x, y, z)
        
        if note then 
            local current = data.selected[2] or tostring(data.selected[1])
            engine.noteOn(data.selected[1], music.note_num_to_freq(note), 1, data[data.pattern][data.selected[1]].params[current].sample)
        end
        
        if sequencer_metro.is_running and note and PATTERN_REC then 
            local tr = data.selected[1]
            local pos = data[data.pattern].track.pos[tr]
            place_note(tr, pos, note)
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

      if view.steps_engine or view.sampling then
      
      if SHIFT then
        
        if z == 1 then
          if x == 16 then
            data[data.pattern].track.mute[y] = not data[data.pattern].track.mute[y]
            if data[data.pattern].track.mute[y] then 

              engine.noteOff(choke[y])
            end
          else
            if x < 8 then
              data[data.pattern].track.div[y] = x
              data[data.pattern][y].params[tostring(y)].div = x
              sync_tracks(y)
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
      else 
     
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
              
            data.pattern = x
            ptn_copy = false
            data.metaseq.from = x
            data.metaseq.to = x
            
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
    
  end
  
end

function g.redraw()
  local glow = util.clamp(blink, 5, 15)
  
  g:all(0)
  
  if view.notes_input then 
      linn.grid_redraw(g)
  end
  
  for y = 1, 7 do 
    for x = 1, 16 do 
      if view.notes_input then 
        
      elseif not view.patterns then
        if SHIFT then
                        
            if y < 8 and x < 8 then
              g:led(x, y, 3)
            end
          
            g:led(data[data.pattern].track.div[y], y, 15)
            g:led(16, y, data[data.pattern].track.mute[y] and 15 or 6 )

        elseif ALT then
          
            local t_start = get_tr_start(y)
            local t_len  = get_tr_len(y)
            if x >= t_start and x <= t_len then
              g:led(x, y, 3)
            end
        
        elseif not SHIFT then
          -- main
          local substeps = have_substeps(y, x)
          
          if substeps then 
            
              local t_start = get_tr_start(y)
              local t_len  = get_tr_len(y)
              local level = data.selected[1] == y and data.selected[2] == x and 15 
              or (x < t_start or x > t_len) and 5
              or data[data.pattern].track.mute[y] and 5
              or 10
              
              g:led(x, y, level ) 
          end
        end

      else
          -- patterns
          local level =
          data.pattern == x and sequencer_metro.is_running and  util.clamp(blink, 5, 14)
          or (x >= data.metaseq.from and x <= data.metaseq.to) and 9 
          or data.pattern == x and 15 
          or 3
          
          g:led(x, 1, level)

      end
    end
    -- playhead
    if (not view.patterns and not view.notes_input) and sequencer_metro.is_running and not SHIFT then
      local pos = math.ceil(data[data.pattern].track.pos[y] / 16)
      local level = have_substeps(y, pos) and 15 or 6
      if not data[data.pattern].track.mute[y] then g:led(pos, y, level) end
    end
  end
  
  g:led(1, 8,  sequencer_metro.is_running and 15 or 6 )
  g:led(3, 8,  (view.notes_input and PATTERN_REC) and glow or view.notes_input and 6 or 0)
  g:led(8, 8,  view.steps_engine and 15  or  6)
  g:led(9, 8,  view.notes_input and 15 or  6)
  g:led(10, 8, view.sampling and 15 or 6)
  g:led(11, 8, view.patterns and 15 or 6)

  g:led(13, 8, MOD and glow or 6 )
  g:led(15, 8, ALT and glow  or 6 )
  g:led(16, 8, SHIFT and glow  or 6 )
  
  
  g:refresh()

end

