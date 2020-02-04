-- 
-- engines
-- @its_your_bedtime
--

local sampling = {
  playing = false,
  recording = false,
  pos = 0,
  start = 0, 
  length = 15,
  mode = 1,
  source = 1,
  slot = 1, 

}



function sampling.phase(x)
  sampling.pos = x
end

function sampling.init()
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
    softcut.level_slew_time(i,00)
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
  softcut.event_phase(function(x) print(x) sampling.pos = x end)
  --softcut.poll_start_phase()

end


function sampling:set_mode()
  if self.mode == 1 then -- stereo
  -- set softcut to stereo inputs
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)

  elseif self.mode == 2 then -- mono L + R
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 1)

  elseif self.mode == 3 then -- mono - L
    softcut.level_input_cut(1, 1, 1)
    softcut.level_input_cut(2, 1, 0)
    softcut.level_input_cut(1, 2, 1)
    softcut.level_input_cut(2, 2, 0)

  elseif self.mode == 4 then -- mono - R
    softcut.level_input_cut(1, 1, 0)
    softcut.level_input_cut(2, 1, 1)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 1)

  end
end

function sampling:set_source()
  if self.source == 1 then -- ext
    audio.level_adc_cut(1)
    audio.level_eng_cut(0)
  elseif self.source == 2 then -- int
    audio.level_adc_cut(0)
    audio.level_eng_cut(1)
  end
end


function sampling:rec(state)
  self.recording = state
  
  softcut.poll_start_phase()
  for i = 1, 2 do
    if self.recording then
       self:clear()
       softcut.loop_start(i, 0)
       softcut.loop_end(i, 60)
       softcut.position(i, 0)
       softcut.rec(i, 1)
       softcut.play(i, 1)
    else
        self.start = 0
        self.length = self.pos
        self.recording = false
        
        softcut.poll_stop_phase()
        softcut.rec(i, 0)
        softcut.play(i, 0)
        softcut.position(i, self.start)
    end
  end

end


function sampling:play(state)
  for i = 1, 2 do
    if state then
        softcut.poll_start_phase()
        self.playing = true
        self.pos = self.start 
        softcut.position(i, self.start)
        softcut.play(i, 1)
    else
        self.playing = false
        softcut.poll_stop_phase()
        softcut.play(i, 0)
    end
  end
end


function sampling:set_start()
  for i = 1, 2 do
    softcut.position(i, self.start)
    softcut.loop_start(i, x)
  end
end


function sampling:set_length()
  for i = 1, 2 do
    if self.pos > self.length then 
        softcut.position(i, self.start)
    end
    softcut.loop_end(i, self.length)
  end
end


function sampling:clear()
  self.start = 0
  self.length = 15
  self.pos = 0
  softcut.buffer_clear(1)
  softcut.buffer_clear(2)
  for i = 1, 2 do
    softcut.position(i, self.start)
  end
  
end


function sampling.save_and_load(slot)
  sampling:play(false)
  sampling:rec(false)
  
  local PATH = _path.audio .. 'takt/'
  if not util.file_exists(PATH) then util.make_dir(PATH) end
  local name = 'sample_' ..  #util.scandir(PATH)
  --local name = os.date('%m%d%H%M') ..'_'.. slot 
  
  if mode == 1 or mode == 2 then
    softcut.buffer_write_stereo (PATH .. name, sampling.start, sampling.length)
  elseif mode == 3 then
    softcut:buffer_write_mono (PATH .. name, sampling.start, sampling.length, 1)
  elseif mode == 4 then
    softcut:buffer_write_mono (PATH .. name, sampling.start, sampling.length, 2)
  end
  
  local saved = false
  repeat
    local ch, len = audio.file_info(PATH .. name)
    saved = util.round(len / 48000, 0.1) >= util.round(sampling.length, 0.1) and true or false
  until saved
  
  --Timber.load_sample(sampling.slot, PATH .. name)
  
end

return sampling