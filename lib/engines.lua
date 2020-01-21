-- 
-- engines
-- @its_your_bedtime
--

local engines = {}
local NUM_SAMPLES = 100 
local playing = false
local recording = false
local position = 0
local start = 0
local length = 60
local wait_metro 
local mode = 1

function unrequire(name)
  package.loaded[name] = nil
  _G[name] = nil
end

unrequire("lib/timber_takt_engine")
local Timber = include("lib/timber_takt_engine")
engine.name = "Timber_Takt"

engines.set_bpm = function(bpm)
    Timber.set_bpm(bpm)
end


function engines.load_folder(file, add)
  
  local sample_id = 0
  if add then
    for i = NUM_SAMPLES - 1, 0, -1 do
      if Timber.samples_meta[i].num_frames > 0 then
        sample_id = i + 1
        break
      end
    end
  end
  
  Timber.clear_samples(sample_id, NUM_SAMPLES - 1)
  
  local split_at = string.match(file, "^.*()/")
  local folder = string.sub(file, 1, split_at)
  file = string.sub(file, split_at + 1)
  
  local found = false
  for k, v in ipairs(Timber.FileSelect.list) do
    if v == file then found = true end
    if found then
      if sample_id > 35 then
        print("Max files loaded")
        break
      end
      -- Check file type
      local lower_v = v:lower()
      if string.find(lower_v, ".wav") or string.find(lower_v, ".aif") or string.find(lower_v, ".aiff") then
        print(sample_id,folder .. v )
        Timber.load_sample(sample_id, folder .. v)
        params:set('play_mode_' .. sample_id, 4)
        sample_id = sample_id + 1
      else
        print("Skipped", v)
      end
    end
  end
end

engines.phase = function(t, x)
  --if playing then 
    position = x 
    
    if position == length then
      position = start
      for i = 1, 2 do 
        softcut.position(i, start)
        softcut.play(i, 0)
        softcut.rec(i, 0)
        
      end
      playing = false
      recording = false
    end
  --end
  --if recording then 
    --position = x
  --end
end


function engines.get_pos()
    return position
end

function engines.get_len()
    return length
end

function engines.get_state()
    return recording or playing and true or false
end


function engines.init()
  -- timbers
  wait_metro = metro.init()
  wait_metro.time = 1
  wait_metro.count = 1

  params:add_trigger('load_f','+ Load Folder')
  params:set_action('load_f', function() Timber.FileSelect.enter(_path.audio, function(file)
  if file ~= "cancel" then engines.load_folder(file, add) end end) end)

  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 3
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  params:add_separator()
  Timber.add_params()
  for i = 0, NUM_SAMPLES - 1 do
    local extra_params = {
      {type = "option", id = "launch_mode_" .. i, name = "Launch Mode", options = {"Gate", "Toggle"}, default = 1, action = function(value)
        Timber.setup_params_dirty = true
      end},
    }
    params:add_separator()
    Timber.add_sample_params(i, true, extra_params)
    --params:set('play_mode_' .. i, 4)
    --params:set('amp_env_sustain_' .. i, 0)
  end
  -- softcut 
  audio.level_cut(0.5)
  audio.level_adc_cut(1)
  audio.level_eng_cut(0)
  softcut.level_input_cut(1, 1, 1)
  softcut.level_input_cut(2, 1, 0)
  softcut.level_input_cut(1, 2, 0)
  softcut.level_input_cut(2, 2, 1)  
  softcut.pan(1,-1)
  softcut.pan(2,1)

  for i=1, 2 do
    softcut.level(i,1)
    softcut.level_slew_time(i,0.1)
    softcut.play(i, 0)
    softcut.rate(i, 1)
    softcut.rate_slew_time(i,0.5)
    softcut.loop_start(i, 0)
    softcut.loop_end(i, 60)
    softcut.loop(i, 0)
    softcut.fade_time(i, 0.1)
    softcut.rec(i, 0)
    softcut.rec_level(i, 0.7)
    softcut.pre_level(i, 0)
    softcut.position(i, 0)
    softcut.buffer(i, i)
    softcut.enable(i, 1)
    softcut.filter_dry(i, 1)
  end

  softcut.phase_quant(1, .01)
  softcut.event_phase(engines.phase)

end


function engines.set_mode(mode)
  if mode == 1 then -- stereo
  -- set softcut to stereo inputs
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)
    mode = 1
  elseif mode == 2 then -- mono L + R
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 1)
    mode = 2
  elseif mode == 3 then -- mono - L
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 0)
    mode = 3
  elseif mode == 4 then -- mono - R
    softcut.level_input_cut(1, 1, 0)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)
    mode = 4
  end
end

function engines.set_source(src)
  if src == 1 then -- ext
    audio.level_adc_cut(1)
    audio.level_eng_cut(0)
  elseif src == 2 then -- int
    audio.level_adc_cut(0)
    audio.level_eng_cut(1)
  end
end


function engines.rec(state)
  recording = state
  for i = 1, 2 do
    if state then
        engines.clear()
       recording = true
       softcut.poll_start_phase()
          --softcut.position(i, 0)
        softcut.rec(i, 1)
    else
        length = position
        recording = false
        softcut.poll_stop_phase()
        softcut.rec(i, 0)
    end
  end

end


function engines.play(state)
  for i = 1, 2 do
    if state then
       playing = true
       softcut.poll_start_phase()
        position = start 
        softcut.position(i, start)
        softcut.play(i, 1)
    else
        playing = false
        softcut.poll_stop_phase()
        softcut.play(i, 0)
    end
  end
end


function engines.set_start(x)
  start = x
  for i = 1, 2 do
    softcut.loop_start(i, x)
  end
end


function engines.set_length(x)
  length = x
  for i = 1, 2 do
    softcut.loop_end(i, x)
  end
end


function engines.clear()
  start = 0
  length = 60
  position = 0
  softcut.buffer_clear()
  for i = 1, 2 do
    softcut.position(i, start)
  end
  
end


function engines.save_and_load(slot)
  
  local PATH = _path.audio .. 'takt/'
  if not util.file_exists(PATH) then util.make_dir(PATH) end
  local name = 'sample_' ..  #util.scandir(PATH)
    
  --print(mode)
  if mode == 1 or mode == 2 then
    softcut.buffer_write_stereo (PATH .. name, start, length)
  elseif mode == 3 then
    softcut:buffer_write_mono (PATH .. name, start, length, 1)
  elseif mode == 4 then
    softcut:buffer_write_mono (PATH .. name, start, length, 2)
  end
  


  wait_metro.event = function(stage)
    --print('saved')
    Timber.load_sample(slot, PATH .. name)
    params:set('play_mode_' .. slot, 3)
    engines.clear()
  end
    
  wait_metro:start()
  
end


return engines