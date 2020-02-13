-- 
-- sampler
-- @its_your_bedtime
--

local sampler = {
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
        
}

local load_sample = include("lib/timber_takt").load_sample
local wait_metro 

sampler.phase = function(t, x)
    sampler.pos = x 

    if sampler.pos >= sampler.length then
      sampler.pos = sampler.start
      
      for i = 1, 2 do 
        softcut.position(i, sampler.start)
        softcut.play(i, 0)
        softcut.rec(i, 0)
      end
    end
end


function sampler.get_pos()
    return sampler.pos
end

function sampler.get_len()
    return sampler.length
end

function sampler.get_state()
    return recording or playing and true or false
end


function sampler.init()
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
  softcut.event_phase(sampler.phase)
  
  wait_metro = metro.init()
  wait_metro.time = 0.01
  wait_metro.count = -1
  sampler.rec = false
end


function sampler.set_mode()
  local mode = sampler.mode
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

function sampler.set_source()
  local src = sampler.source
  if src == 1 then -- ext
    audio.level_adc_cut(1)
    audio.level_eng_cut(0)
  elseif src == 2 then -- int
    audio.level_adc_cut(0)
    audio.level_eng_cut(1)
  end
end


function sampler.rec(state)
  if state == 1 then
    sampler.rec = not sampler.rec 
  end
  
    for i = 1, 2 do
      if sampler.rec then
         sampler.clear(1)
         softcut.loop_start(i, 0)
         softcut.loop_end(i, 60)
         softcut.poll_start_phase()
         softcut.position(i, 0)
         softcut.rec(i, 1)
      else
          sampler.length = sampler.pos
          sampler.rec_length = sampler.pos
          softcut.poll_stop_phase()
          softcut.rec(i, 0)
          sampler.start = 0
          softcut.position(i, 0)
      end
    end
  
end


function sampler.play(state)
  sampler.play = state == 1 and true or false
  for i = 1, 2 do
    if sampler.play then
        softcut.poll_start_phase()
        softcut.position(i, sampler.start)
        softcut.play(i, 1)
    else
        sampler.pos = 0
        softcut.poll_stop_phase()
        softcut.play(i, 0)
    end
  end
end


function sampler.set_start(x)
  sampler.start = x
  for i = 1, 2 do
    softcut.position(i, x)
    softcut.loop_start(i, x)
  end
end


function sampler.set_length(x)
  sampler.length = x
  for i = 1, 2 do
    if sampler.pos > sampler.length then 
        softcut.position(i, sampler.start)
    end
    softcut.loop_end(i, sampler.length)
  end
end


function sampler.clear(state)
  if state ~= 1 then return false end
  sampler.start = 0
  sampler.length = sampler.max_length
  sampler.rec_length = 0
  sampler.pos = 0
  softcut.buffer_clear()
  for i = 1, 2 do
    softcut.position(i, 0)
  end
  
end


function sampler.save_and_load(state)
  if state == 1 then 
    local PATH = _path.audio .. 'takt/'
    if not util.file_exists(PATH) then util.make_dir(PATH) end
    local name = 'sample_' ..  #util.scandir(PATH) .. '.wav'
    local start = sampler.start
    local length = sampler.length
    local mode = sampler.mode
    local slot = sampler.slot
  
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
        load_sample(slot, PATH .. name)
        params:set('play_mode_' .. slot, 2)
        wait_metro:stop()
      end
    end
      
    wait_metro:start()
  end
end

return sampler