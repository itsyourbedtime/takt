-- 
-- engines
-- @its_your_bedtime
--

local engines = {
        
        sc = {
              play = false,
              rec = false,
              pos = 0,
              start = 0,
              length = 60,
              max_length = 60,
              rec_length = 0,
              mode = 1, 
              source = 1,
              slot = 1,
        },
}


function unrequire(name)
  package.loaded[name] = nil
  _G[name] = nil
end

unrequire("lib/timber_takt")
engine.name = "Timber_Takt"
local Timber = include("lib/timber_takt")
local NUM_SAMPLES = 99 
local wait_metro 

function engines.load_folder(file, add)
  
  local sample_id = 1
  if add then
    for i = NUM_SAMPLES - 1, 0, -1 do
      --print(i)
      if Timber.samples_meta[i].num_frames > 0 then
        sample_id = i + 1
        break
      end
    end
  end
  
  Timber.clear_samples(sample_id, NUM_SAMPLES)
  
  local split_at = string.match(file, "^.*()/")
  local folder = string.sub(file, 1, split_at)
  file = string.sub(file, split_at + 1)
  
  local found = false
  
  for k, v in ipairs(Timber.FileSelect.list) do
    if v == file then found = true end
    if found then
      if sample_id > 100 then
        print("Max files loaded")
        break
      end
      -- Check file type
      local lower_v = v:lower()
      if string.find(lower_v, ".wav") or string.find(lower_v, ".aif") or string.find(lower_v, ".aiff") then
        --print(sample_id,folder .. v )
        Timber.load_sample(sample_id, folder .. v)
        params:set('play_mode_'..sample_id, 4)
        sample_id = sample_id + 1
      else
        print("Skipped", v)
      end
      
    end
    
  end
end


engines.phase = function(t, x)
    engines.sc.position = x 

    if engines.sc.position >= engines.sc.length then
      engines.sc.position = engines.sc.start
      
      for i = 1, 2 do 
        softcut.position(i, engines.sc.start)
        softcut.play(i, 0)
        softcut.rec(i, 0)
      end
    end
end


function engines.get_pos()
    return engines.sc.position
end

function engines.get_len()
    return engines.sc.length
end

function engines.get_state()
    return recording or playing and true or false
end


function engines.init()
  -- timbers

  params:add_trigger('load_f','+ Load Folder')
  params:set_action('load_f', function() Timber.FileSelect.enter(_path.audio, function(file)
  if file ~= "cancel" then engines.load_folder(file, add) end end) end)

  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 3
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  params:add_separator()
  Timber.add_params()
  for i = 1, NUM_SAMPLES do

    params:add_separator()
    Timber.add_sample_params(i, true) 
    
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
  
  wait_metro = metro.init()
  wait_metro.time = 0.01
  wait_metro.count = -1

end


function engines.set_mode()
  local mode = engines.sc.mode
  if mode == 1 then -- stereo
  -- set softcut to stereo inputs
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)
  elseif mode == 2 then -- mono L + R
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 1)
  elseif mode == 3 then -- mono - L
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 0)
  elseif mode == 4 then -- mono - R
    softcut.level_input_cut(1, 1, 0)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)
  end
end

function engines.set_source()
  local src = engines.sc.source
  if src == 1 then -- ext
    audio.level_adc_cut(1)
    audio.level_eng_cut(0)
  elseif src == 2 then -- int
    audio.level_adc_cut(0)
    audio.level_eng_cut(1)
  end
end


function engines.rec(state)
  if state ~= 1 then return false
  else
    engines.sc.rec = not engines.sc.rec 
    for i = 1, 2 do
      if engines.sc.rec then
         engines.clear(1)
         softcut.loop_start(i, 0)
         softcut.loop_end(i, 60)
         softcut.poll_start_phase()
         softcut.position(i, 0)
         softcut.rec(i, 1)
      else
          engines.sc.length = engines.sc.position
          engines.sc.rec_length = engines.sc.position
          softcut.poll_stop_phase()
          softcut.rec(i, 0)
          engines.sc.start = 0
          softcut.position(i, 0)
      end
    end
  end
end


function engines.play(state)
  engines.sc.play = state == 1 and true or false
  for i = 1, 2 do
    if state == 1 then
        softcut.poll_start_phase()
        softcut.position(i, engines.sc.start)
        softcut.play(i, 1)
    else
        engines.sc.position = 0
        softcut.poll_stop_phase()
        softcut.play(i, 0)
    end
  end
end


function engines.set_start(x)
  engines.sc.start = x
  for i = 1, 2 do
    softcut.position(i, x)
    softcut.loop_start(i, x)
  end
end


function engines.set_length(x)
  engines.sc.length = x
  for i = 1, 2 do
    if engines.sc.position > engines.sc.length then 
        softcut.position(i, engines.sc.start)
    end
    softcut.loop_end(i, engines.sc.length)
  end
end


function engines.clear(state)
  if state ~= 1 then return false end
  engines.sc.start = 0
  engines.sc.length = engines.sc.max_length
  engines.sc.rec_length = 0
  engines.sc.position = 0
  softcut.buffer_clear()
  for i = 1, 2 do
    softcut.position(i, 0)
  end
  
end


function engines.save_and_load(state)
  if state == 1 then 
    local PATH = _path.audio .. 'takt/'
    if not util.file_exists(PATH) then util.make_dir(PATH) end
    local name = 'sample_' ..  #util.scandir(PATH) .. '.wav'
    local start = engines.sc.start
    local length = engines.sc.length
    local mode = engines.sc.mode
    local slot = engines.sc.slot
  
    --local name = os.date('%m%d%H%M') ..'_'.. slot 
    
    print('saving', start, length)
    print(PATH..name)
    if mode == 1 then
      softcut.buffer_write_stereo (PATH .. name, start, length)
    elseif mode == 2 or mode == 3 then
      softcut.buffer_write_mono (PATH .. name, start, length, 1)
    elseif mode == 4 then
      softcut.buffer_write_mono (PATH .. name, start, length, 2)
    end
    
    wait_metro.event = function(stage)
      local ch, len = audio.file_info(PATH .. name)
      local ready = util.round(len / 48000, 0.1) == util.round(length, 0.1) and true or false
  
      if ready then 
        Timber.load_sample(slot, PATH .. name)
        params:set('play_mode_' .. slot, 2)
        wait_metro:stop()
      end
    end
      
    wait_metro:start()
  end
end


function engines.get_meta(id)
  return Timber.get_meta(id)
end

return engines