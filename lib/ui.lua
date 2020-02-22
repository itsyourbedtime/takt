-- takt ui @its_your_bedtime

local ui = { waveform = {}, in_l = 0, in_r = 0, out_l = 0, out_r = 0, vu_l, vu_r, vu_o_l, vu_o_r }
local note_num_to_name = require ('musicutil').note_num_to_name
local name_lookup = {
  ['SMP'] = 'sample', ['MODE'] = 'play_mode', ['NOTE'] = 'note', ['STRT'] = 'start_frame', ['END'] = 'end_frame', 
  ['FM1'] = 'freq_mod_lfo_1', ['FM2'] = 'freq_mod_lfo_2', ['VOL'] = 'amp', ['PAN'] = 'pan', ['ENV'] = 'env', 
  ['AMP'] = 'amp_mod_lfo_1', ['AM2'] = 'amp_mod_lfo_2', ['SR'] = 'quality', ['TYPE'] = 'filter_type', ['CFM'] = 'filter_freq_mod_lfo_2', 
  ['RVRB'] = 'reverb_send', ['DEL'] = 'delay_send', 

}
local midi_name_lookup = { 
  [1] = 'note', [2] = 'velocity', [3] = 'length', [4] = 'channel', [5] = 'device', [6] = 'program_change', 
  [7] = 'cc_1_val', [8] = 'cc_2_val', [9] = 'cc_3_val', [10] = 'cc_3_val', [11] = 'cc_4_val', [12] = 'cc_4_val'
}
local dividers  = {[0] = 'OFF', '1/8', '1/4', '1/2', '3/4', '--', '3/2', '2x' } 

local filter = controlspec.WIDEFREQ

function ui.init()
  ui.vu_l, ui.vu_r, ui.vu_o_l, ui.vu_o_r = poll.set("amp_in_l"), poll.set("amp_in_r"), poll.set("amp_out_l"), poll.set("amp_out_r")
  ui.vu_l.time, ui.vu_r.time, ui.vu_o_l.time, ui.vu_o_r.time = 1 / 24, 1 / 24, 1 / 24, 1 / 24
  
  ui.vu_l.callback = function(val) ui.in_l = util.linlin(0,1, 0, 30, val) end
  ui.vu_r.callback = function(val) ui.in_r = util.linlin(0,1, 0, 30, val) end
  ui.vu_o_l.callback = function(val) ui.out_l = util.linlin(0,1, 0, 30, val) end
  ui.vu_o_r.callback = function(val) ui.out_r = util.linlin(0,1, 0, 30, val)end
  for i = 1, 10 do
    ui.waveform[i] = {0,0}
  end
  ui.reverb = {}
  ui.reverb.orbit = math.fmod(1,2)~=0 and 6 or 15
  ui.reverb.position = 1 <= 2 and 0 or 1 <= 4 and 2 or 4
  ui.reverb.velocity = util.linlin(0, 1, 0.01, 1, 1)
  

end

function ui.start_polls()
  ui.vu_l:start()
  ui.vu_r:start()
  ui.vu_o_l:start()
  ui.vu_o_r:start()
end

function ui.stop_polls()
  ui.vu_l:stop()
  ui.vu_r:stop()
  ui.vu_o_l:stop()
  ui.vu_o_r:stop()
end

local function get_step(x) return (x * 16) - 15 end

local function set_brightness(n, i) screen.level(i == n and 6 or 2) end

local function metro_icon(x, y, pos)
  screen.level(0)
  screen.move(x + 2, y + 5)
  screen.line(x + 7, y)
  screen.line(x + 12, y + 5)
  screen.line(x + 3, y + 5)
  screen.stroke()
  screen.move(x + 7, y + 3)
  screen.line(pos % 4 > 1 and (x + 4) or (x + 10), y ) 
  screen.stroke()

end


function ui.head(params_data, data, view, k1, rules, PATTERN_REC, preview)
  local tr = data.selected[1]
  local s = data.selected[2]
  local pos = data[data.pattern].track.pos[tr]
  
  screen.level((not view.sampling and data.ui_index == -6 ) and 5 or 2)  
  screen.rect(1, 0, 20, 7)
  screen.fill()
  screen.level(0)
  
  screen.font_size(6)
  screen.font_face(25)
  
  
  if not s then 
    screen.move(3,6)
    screen.text('P')
    if PATTERN_REC then
    screen.move(7,6)
    screen.level( pos % 8 or 0)
    screen.text('!')
    end
    screen.move(18,6)
    screen.level(0)
    screen.text_right(data.pattern or nil )
    screen.stroke()
    
  else
    screen.move(11,6)
    screen.text_center( tr ..':' .. s )
  end

    screen.level((not view.sampling and data.ui_index == (not s and -5 or -3) ) and 5 or 2)  
    screen.rect(22, 0, 20, 7)
    screen.fill()
    screen.level(0)
  
  if s then 
    screen.move(31,6)
    screen.text_center( dividers[params_data.div] )

else
    screen.move(24, 6)
    screen.text('TR')
    screen.move(40, 6)
    screen.text_right(tr )
  end
  
  screen.stroke()
  
  if s then 
    local rule_name = rules[params_data.rule][1]
    
    screen.level((not view.sampling and data.ui_index == -2 ) and 5 or 2)  
    screen.rect(43, 0, 41, 7)
    screen.fill()
    screen.level(0)
    if string.len(rule_name) < 5 then
      screen.move(45, 6)
      screen.text('RULE')
      screen.move(82, 6)
      screen.text_right(rule_name)
    else
      screen.move(45, 6)
      screen.text(rule_name)
    end
    
  else
    screen.level((not view.sampling and data.ui_index == -4) and 5 or 2)  
    screen.rect(43, 0, 25, 7)
    screen.fill()
    screen.level(0)
    metro_icon(42,1, pos)
    screen.move(66, 6)
    screen.text_right(data[data.pattern].bpm)
    
    
  end

  screen.stroke()
  
  if not s then
    screen.level((not view.sampling and data.ui_index == -3) and 5 or 2)  
    screen.rect(69, 0, 15, 7)
    screen.fill()
    screen.level(0)
    screen.move(76,6)
    screen.text_center(dividers[data[data.pattern].track.div[tr]])
    screen.stroke()
  end
  
  if not k1 then
    screen.level((not view.sampling and data.ui_index == -1) and 5 or 2)  
    screen.rect(85, 0, 9, 7)
    screen.fill()
    screen.level(0)
    screen.move(89,6)
    screen.text_center(params_data.retrig)
    screen.stroke()
  
      for i = 1, 16 do
        local offset_y = i <= 8 and 0 or 4
        local offset_x = i <= 8 and 0 or 8
        local st = s and get_step(data.selected[2]) or util.round(data[data.pattern].track.pos[tr], 16) + 1
        local step = data[data.pattern][tr][st + (i - 1 )]
        
        screen.level((not view.sampling and data.ui_index == 0) and 5 or 2)
        if step == 1 then
          screen.rect(92 + ((i - offset_x) * 4), offset_y + 1, 2, 2) 
          screen.stroke()
        else
          screen.rect(91 + ((i - offset_x) * 4), offset_y, 3, 3) 
          screen.fill()
        end
    end
  else
    if preview then
      screen.level(2)
      screen.rect(85, 0, 41, 7)
      screen.fill()

      screen.level(0)

      screen.move(88, 6)
      screen.line(88, 1)
      screen.stroke()
      screen.move(88, 1)
      screen.line(91, 4)
      screen.stroke()
      screen.move(91,3)
      screen.line(88, 6)
      screen.stroke()

      screen.move(97,6)
      screen.text('PREVIEW')
      screen.stroke()


    else
      screen.level(data.ui_index == -2 and 5 or 2)  
      screen.rect(85, 0, 20, 7)
      screen.fill()
      screen.level(0)
      screen.move(95,6)

      screen.text_center(dividers[data[data.pattern].sync_div])
      screen.stroke()
      screen.level(data.ui_index == -1 and 5 or 2) 

      if tr < 8 then
        screen.rect(106, 0, 20, 7)
        screen.fill()
        screen.level(0)
        screen.rect(109 , 3, 15, 2)
        screen.stroke()
        screen.level(data.ui_index == -1 and 5 or 2) 
        screen.pixel(108, 2)
        screen.pixel(108, 4)
        screen.pixel(123, 2)
        screen.pixel(123, 4)
        screen.fill()
        screen.level(1)

        screen.rect(109, 3, util.linlin(-99, 0, 0, 14, data[data.pattern][tr].params[tostring(tr)].sidechain_send), 1)

        screen.fill() 
      else
        screen.rect(106, 0, 20, 7)
        screen.fill()

      end
    end
  end
end

function ui.draw_env(x, y, t, params_data, ui_index)
    local atk, dec, sus, rel
    atk = params_data.amp_env_attack
    dec = params_data.amp_env_decay
    sus = params_data.amp_env_sustain
    rel = params_data.amp_env_release
    
    local sy = util.clamp(y - (sus * 10) + 2, 0, y )
    local attack_peak = x + atk * 2
    
    screen.level(2)
    screen.rect(x - 1, y - 15, 40, 16)
    screen.stroke()
    
    
    screen.level(ui_index == 9 and 15 or 1)
    screen.move(x,y)
    screen.line(attack_peak, y - 14)
    screen.stroke()
    screen.level(ui_index == 10 and 15 or 1)
    screen.move(attack_peak, y - 14)
    screen.line(x + ((atk / 2) + dec) * 3 + 3, sy)
    screen.stroke()
    screen.level(ui_index == 11 and 15 or 1 )
    screen.move(x + ((atk / 2) + dec) * 3 + 2, sy)
    screen.line(util.clamp(x + (rel) * 3 + 24, 0,  x+38), sy )
    screen.stroke()
    screen.level(ui_index == 12 and 15 or 1)
    screen.move(util.clamp(x + ( rel) * 3 + 24, 2, x+38), sy)
    screen.line(util.clamp(x + ( rel) * 2 + 38, 0, x+38), y)
    screen.stroke()
  
end

function ui.draw_filter(x, y, params_data, ui_index)

    screen.level(2)
    screen.rect(x - 1, y - 15, 40, 16)
    screen.stroke()

    local sample = params_data.sample
    local cut_m = filter:unmap(params_data.filter_freq)
    local cut = util.linexp(0,1,1,34, cut_m )--/ 1200
    local res = util.linlin(0,1,0,5, params_data.filter_resonance)


    screen.level(1)

    if params_data.filter_type == 1  then
        local t = x + cut 
        screen.level(ui_index == 17 and 15 or 1)
        screen.move(x - 1, y - 9)
        screen.curve (t, y - 9, t, y - 9 - (res / 2), t + 1, y - 9 - res)
        screen.stroke()
        screen.level(ui_index == 18 and 15 or 1)
        screen.move(t + 1, y - 9 - res )
        screen.line(t + 4, y)
        screen.stroke()
        

  elseif params_data.filter_type == 2 then
        cut = 34 - cut 
        local t = x + cut
        screen.level( ui_index == 18 and 15 or 1)
        screen.move(t - 1, y)
        screen.line(t , y - 9 - res)
        screen.stroke()

        screen.move(x + 38 , y - 9)
        screen.level(ui_index == 17 and 15 or 1)
        screen.curve (t, y - 9, t, y - 9 - (res / 2), t, y - 9 - res)

        screen.stroke()
        screen.close()
        
        

  end
  
end

function ui.draw_mode(x, y, mode, index, lock)
    set_brightness(16, index)
    screen.rect(x - 3, y - 15, 20, 17)
    screen.fill()
    screen.level(0)
    screen.move(x, y - 8)
    screen.text('MODE')
    screen.stroke()
    --screen.level(0)
    
    local lvl = lock == true and 15 or 0 --
    screen.level(lvl)
    if mode == 1  or mode == 2 then -- loop
      
      screen.move(x + 3, y)
      screen.line(x + 5, y)
      screen.move(x + 5, y + 1)
      screen.line(x + 8, y + 1)
      screen.move(x + 8, y)
      screen.line(x + 10, y)
      screen.move(x + 11, y - 1)
      screen.line(x + 11, y - 3)
      screen.move(x + 8, y - 3)
      screen.line(x + 10, y - 3)
      screen.move(x + 5, y - 4)
      screen.line(x + 8, y - 4)
      screen.move(x + 3, y - 3)
      screen.line(x + 5, y - 3)
      screen.move(x + 4, y - 2)
      screen.line(x + 4, y - 6)
      screen.move(x + 4, y - 2)
      screen.line(x + 7, y - 2)  

    elseif mode == 3 or mode == 4 then -- oneshot
    
      screen.move(x + 1, y - 2)
      screen.line(x + 11, y - 2)
      screen.move(x + 9, y - 5)
      screen.line(x + 12, y - 2)
      screen.move(x + 9, y  )
      screen.line(x + 12, y - 3)
      
    end
    screen.stroke()
end

local function draw_start_end_markers(x, y, w, h, ui_index, params_data, meta, lock)
  local num_frames = meta.num_frames
  local start_x = x + 0.5 + util.round((params_data.start_frame / num_frames) * (w - 1))
  local end_x = x + 0.5 + util.round((params_data.end_frame / num_frames) * (w - 1))

  set_brightness(3, ui_index)
  screen.move(start_x, y)
  screen.line(start_x, y + h )
  screen.stroke()
 
  local arrow_direction = 1
  if start_x > end_x then arrow_direction = -1 end
  local clamp = util.clamp(start_x + 0.5 * arrow_direction, 0, (x + w) - 1)
  screen.move(clamp, y + 1)
  screen.line_rel(2 * arrow_direction, 2)
  screen.stroke()

  screen.pixel(clamp , y + 3)

  screen.stroke()
  
  set_brightness(4, ui_index)
  screen.move(end_x, y )
  screen.line(end_x, y + h)
  screen.stroke()

  
end


function ui.draw_waveform(x, y, params_data, ui_index, meta, lock)
    screen.level(2)
    screen.rect(x + 1 , y + 1, 40, 16)
    screen.stroke()
    if meta.waveform[1] then
      screen.level(1)
      
      for i = 1, 39 do
          local w = meta.waveform[i] or {0,0}
          screen.move(x + 1 + i, y + 16)
          screen.line(x + 1 + i, y + (16 - w[2]*15))
          screen.stroke()
      end
    
      screen.level(2)
      for _, v in pairs(meta.positions) do
        local position_x = (x + 1 + util.linlin(0, 1, 0, 39, v))
        screen.move(position_x, y + 16)
        screen.line(position_x, y + 1 )
      end
      screen.stroke()
      draw_start_end_markers(x + 1, y + 1, 39, 15, ui_index, params_data, meta, lock)
    else
      if ui_index == 3 or ui_index == 4 then
        set_brightness(ui_index, ui_index)
      end
      screen.move(x + 6, y + 11)
      screen.text('+ LOAD')
      screen.stroke()
    end
end

function ui.draw_note(x, y, params_data, index, ui_index, lock)
  set_brightness(index, ui_index)
  screen.rect(x,  y, 20, 17)
  screen.fill()
  local offset = params_data.detune_cents and util.linlin(-100,100,-3,3, params_data.detune_cents) or 0
  screen.level(0)
  screen.rect(x + 7 + offset, y + 6, 3, 2)
  screen.rect(x + 8 + offset, y + 6, 3, 1)
  screen.rect(x + 10 + offset, y +2, 1, 4)
  screen.rect(x + 11 + offset, y + 3, 1, 1)
  screen.rect(x + 12 + offset, y + 4, 1, 1)
  screen.fill()
  
  local note_name = params_data.note
  local oct = math.floor(note_name / 12 - 2) == 0 and '' or math.floor(note_name / 12 - 2)
  screen.level(0)

  local lvl = lock == true and 15 or 0 --

  screen.level(lvl)
  screen.move(x + 9, y + 15)
  screen.text_center(oct ..  note_num_to_name(note_name):gsub('♯', '#'))
  screen.stroke()
 
end

function ui.draw_pan(x, y, params_data, ui_index, menu_index, lock)
  set_brightness(menu_index, ui_index)
  screen.rect(x,  y, 20, 17)
  screen.fill()
  screen.level(0)
  screen.move(x + 9, y + 7)
  screen.text_center('PAN')
  
  local pan = params_data.pan * 5

  
  local lvl = lock == true and 15 or 0 --

  screen.move(x + 4, y + 13)
  screen.line(x + 15, y + 13)
  screen.stroke()
  screen.level(lvl)
  local pan_abs = math.abs(pan)
  
  if util.round(pan_abs,0.5) > 0.5 then screen.rect(x + 9, y + 11, 1, 3) end
  screen.rect(x + 9 + pan, y + 11 - (pan_abs/4), 1, 3 + (pan_abs/2))

  screen.fill()
 
end


function ui.tile(index, name, value, ui_index, lock, custom)
  
  local x = index > 14 and (21 * index) - 314
          or (index == 13 or index == 14) and (21 * index) - 188
          or index > 6 and (21 * index) - 146
          or (21 * index) - 20
          
  local y = index > 14 and 44 or index > 6 and 26 or 8
  local x_ext =  index == 4 and 6 or index == 3 and 2 or 0
  
  
  set_brightness(index, ui_index)
  screen.rect(x , y,  20, 17)
  screen.fill()

  screen.level(custom and custom == ui_index and 15 or 0) 
  screen.move( x  + 10, y + 7)
  screen.text_center(name)
  screen.move( x  + 10,y + 15)
  
  local lvl = lock == true and 15 or 0 --
  screen.level(lvl)
  


  if (type(value) == 'number'and value ~= math.floor(value)) and index ~= 7 then 
    local value = string.sub(value, 2)
  end

  if string.len(tostring(value)) > 4 then local value = util.round(value, 0.01) end
  
  screen.text_center(value)
  screen.stroke()
  
end


local count = { 1, 1}

function lfo(x, y, n, f, s, amp, width)
    local left = x + 5
    local top = y + 5

    local lowamp = 0.5
    local highamp = 1 + amp

    --screen.level(0)
    local width = width and width or 10
    
    count[n] = (count[n] + 0.3)  + util.expexp(0.05, 20, 0.11, 0.13, f)  

    local i = 2
    for j = 1, width do
      local amp = math.sin((count[n]  * (i == 1 and 1 or 2) / 0.3 + j / width)  * (i == 1 and 2 or 4) * math.pi) 
        * util.linlin(1, width / 2, lowamp, highamp, j < (width / 2) and j or width - j) - 0.75 
        * util.linlin(1, width / 2, lowamp, highamp, j < (width / 2) and j or width - j)-(util.linexp(0, 1, 0.5, 6, j/width) * 0) 
        or 0

      screen.pixel(left - 1 + j, top + amp)
    end
    screen.fill()
end



function ui.draw_level_meter(x, y, minv, maxv, value, index, ui_index, lock, n)
    if n then
      set_brightness(index, ui_index)
      screen.rect(x,  y, 20, 17)
      screen.fill()
    
      screen.level(0)
      screen.move(x + 10, y + 7)
      screen.text_center(n)
      screen.stroke()
      
      local lvl = lock == true and 15 or 0
      screen.level(lvl)
    end
    local h = maxv == 0 and 20 or 0
    screen.rect(x + 4, y + 12, 13, 3)
    screen.stroke()
    
    screen.level(1)
    screen.rect(x + 4, y + 12, util.linlin(minv, maxv, 0, 12, value) , 1)
    screen.rect(x + 4, y + 13, util.linlin(minv, maxv-((maxv+h)/10), 0, 12, value) , 1)
    screen.fill()

    set_brightness(index, ui_index)
    screen.pixel(x + 3, y+ 11)
    screen.pixel(x + 3, y+ 14)
    screen.pixel(x + 16, y+ 11)
    screen.pixel(x + 16, y+ 14)
    screen.fill()
end

function ui.draw_volume(x, y, minv, maxv, value, index, ui_index, lock, n)

    set_brightness(index, ui_index)
    screen.rect(x,  y, 20, 17)
    screen.fill()
    screen.level(0)

    screen.rect(x + 6, y + 4, 1,3)
    screen.rect(x + 7, y + 3, 1,5)
    screen.rect(x + 8, y + 2, 1,7)
    screen.fill()
    local vol = util.linlin(minv,maxv,0,3, value)
    if vol < 0.4 then
      screen.move(x + 10, y + 4)
      screen.line(x + 13, y + 7)
      screen.stroke()
      screen.move(x + 10, y + 7)
      screen.line(x + 13, y + 4)
      screen.stroke()
    end
    for i = 0, vol do
      local x = x + 8 + (i * 2)
      local y =  y + 6 - i
      if i > 1 then 
        screen.pixel(x - 1, y - 1)
        screen.pixel(x - 1, y + (i *1.7))
      end
      screen.rect(x, y, 1, i > 1 and (i*1.7) or i )
    end
    screen.fill()
    ui.draw_level_meter(x, y, minv, maxv, value, index, ui_index, lock)
end


function ui.draw_lfo(x, y, lfo_num, params_data, index,  ui_index, lock, n) 
  set_brightness(index, ui_index)
  screen.rect(x,  y, 20, 17)
  screen.fill()

  local value = params_data[name_lookup[n]]

  if index == ui_index then
    local shape = params:get('lfo_'.. lfo_num .. '_wave_shape')
    local freq = params:get('lfo_'.. lfo_num ..'_freq')
    screen.level(0)
    lfo(x, y, lfo_num, freq, shape, 0)
    
  else
    screen.level(0)
    screen.move(x + 5, y + 7)
    screen.text(n)
    screen.stroke()
  end
  local lvl = lock == true and 15 or 0 --

  screen.level(lvl)
  ui.draw_level_meter(x, y, 0, 1, value, index,  ui_index, lock)
end

local sr_types = { '8k', '16k', '26k', '32k', '48k' }
local f_types = { 'LPF', 'HPF' } 


function ui.is_lock(t, params_data)
  local lock = false
  if params_data.default then
    local tile_name = t[2]
    local tile_value = t[3]
    local param_name = name_lookup[t[2]] 

    local default = params_data.default[param_name]

    if tile_name == 'SR' then
      lock = sr_types[default] ~= tile_value and true or false
    elseif tile_name == 'TYPE' then
      lock = f_types[default] ~= tile_value and true or false
    else
      lock = (lock == false and default ~= params_data[param_name]) and true or false
    end
  end

  return lock
end


---- fx 


function ui.draw_delay(x, y, index )
  screen.level((index > 11 and index < 15) and 6 or 2)
  screen.rect(x,  y, 20, 17)
  screen.fill()
  screen.level(0)


  screen.level(0)
  screen.move(x + 10, y + 7)
  if  index > 11  and index < 15 then
    local n = {[12] = "VOL", [13] = "TIME",[14] = 'FBK'} 
    screen.text_center(n[index])
  else
    screen.text_center('DEL')
  end
  local v = { [12] = { params:get('delay_level'), -99, 0} , [13] = {params:get('delay_time'), 0, 3 } ,[14] = {params:get('delay_feedback'), 0, 1},}

  local i = (index > 11 and index < 15) and index or 12
  ui.draw_level_meter(x, y, v[i][2], v[i][3], v[i][1] or v[i][1], i, index)

  local vol = util.linlin(-99, 0, 1, 5, params:get('delay_level'))
  local feedback = util.linlin(0, 1, 0, 4, params:get('delay_feedback'))
  local time = util.round(util.linlin(0.0001, 3, 0.5, 8 - feedback, params:get('delay_time')))
  screen.level(2)
  screen.rect(x + 22, y + 1, 40, 16)
  screen.stroke()
  for i = 1, 2 + feedback do
    local lvl = (index == 13 and i == 2+feedback) and 6 or (index == 14 and i == 1) and 6 or 1

    screen.level(0)
    screen.circle(x  + (43+((time + feedback)*2)) - (i*(1 + time)) , y + 9,  1 + vol )
    screen.fill()
    screen.level(lvl)
    screen.circle(x  + (43+ ((time + feedback)*2))- (i*(1 + time)) , y + 9, 1 + vol)
    screen.stroke()
  end
end


function ui.midi_screen(params_data, ui_index, tracks, steps)

   local tile = {
      {1, 'NOTE', function(i, _, lock) ui.draw_note(1, 8, params_data,i, ui_index, lock) end },
      {2, 'VEL',  params_data.velocity },
      {3, 'LEN',   params_data.length},
      {4, 'CH',   params_data.channel },
      {5, 'DEV',  params_data.device },
      {6, 'PGM',  params_data.program_change },
      {7, 'CC' .. params_data.cc_1, params_data.cc_1_val },
      {8, 'CC' .. params_data.cc_2, params_data.cc_2_val },
      {9, 'CC' .. params_data.cc_3, params_data.cc_3_val },
      {10,'CC' .. params_data.cc_4, params_data.cc_4_val },
      {11,'CC' .. params_data.cc_5, params_data.cc_5_val },
      {12,'CC' .. params_data.cc_6, params_data.cc_6_val },
    }
    
    
   for k, v in pairs(tile) do
        
      local lock = false
      if params_data.default then
         lock = (lock == false and params_data.default[midi_name_lookup[k]] ~= (k == 1 and params_data.note or v[3]) ) and true or false
      end
        
      if v[3] and type(v[3]) == 'function' then
        v[3](v[1], v[2], lock)
      elseif v[3] then
        if v[1]  > 3 and  v[3] < 0 then 
          v[3] = '--' 
        elseif  v[1] == 3 then 
          v[3] = util.round(util.linlin(1, 256, 1, 16,v[3]),0.01)
       -- elseif v[1] > 6 then
         -- local cc = string.sub(v[2], 3)
          --if tonumber(cc) > 100 then  v[2] = 'CC.'.. string.sub(v[2], 4) end
        end
        ui.tile(v[1], v[2], v[3], ui_index, lock , v[1] > 6 and v[1] + 6 or false)
      end
    end
   
    screen.level(2)
    screen.rect(2, 45, 124, 19)
    screen.stroke()
    
    for i = 8, 14 do
      local pos = tracks.pos[i]
        screen.level(1)
        screen.move(3 + (pos / 2.1), 32 + (i+i) - 2)
        screen.line(3 + (pos / 2.1), 32 + (i+i) )
        screen.stroke()
        
    for k,v in pairs(steps[i]) do
        if v == 1 then
          screen.level(5)
          screen.pixel(2 + (k / 2.1), 32 + (i + (i - 1)) )
          screen.fill()
          
          if util.round(k,16) == util.round(pos , 16) then
            screen.level(15)
            screen.pixel(2 + (k / 2.1), 32 + (i + (i - 1)) )
            screen.stroke()
          end
        end
        
      
    end
      
  end
  
end


function ui.main_screen(params_data, ui_index, meta)
  
  local tile = { 
    {1, 'SMP',  params_data.sample},
    {2, 'NOTE', function(i,n,lock) ui.draw_note(22, 8, params_data,i, ui_index, lock) end },
    {3, 'S-E', function(i,n,lock) ui.draw_waveform(43, 8, params_data, ui_index, meta, lock) end },
    {5, 'FM1', function(i,n,lock) ui.draw_lfo(85, 8, 1, params_data, i, ui_index, lock, n) end },
    {6, 'FM2', function(i,n,lock) ui.draw_lfo(106, 8, 2, params_data, i, ui_index, lock, n) end },
    {7, 'VOL', function(i,n,lock) ui.draw_volume(1, 26, -48, 16, params_data[name_lookup[n]], i , ui_index, lock, n) end},
    {8, 'PAN', function(i,n,lock) ui.draw_pan(22, 26, params_data, ui_index, 8, lock) end },
    {9, 'ENV', function(i,n,lock)  ui.draw_env(45, 42, 'AMP', params_data, ui_index) end },
    {13, 'AMP', function(i,n,lock) ui.draw_lfo(85, 26, 1, params_data, i, ui_index, lock, n) end }, 
    {14, 'CFM', function(i,n,lock) ui.draw_lfo(106, 26, 1, params_data, i, ui_index, lock, n) end },
    {15, 'SR', sr_types[params_data.quality] },
    {16, 'MODE', function(i,n,lock) ui.draw_mode(25, 59, params_data.play_mode, ui_index, lock) end },
    {17, 'FILTER', function(lock) ui.draw_filter(45, 60, params_data, ui_index) end },
    {19, 'DEL', function(i,n,lock) ui.draw_level_meter(85, 44, -48, 0, params_data[name_lookup[n]], i,  ui_index, lock, n) end }, 
    {20, 'RVRB', function(i,n,lock) ui.draw_level_meter(106, 44, -48, 0, params_data[name_lookup[n]], i , ui_index, lock, n) end },

  }

  for k, v in pairs(tile) do
    local lock = ui.is_lock(v, params_data )
    if v[3] and type(v[3]) == 'function' then
      v[3](v[1], v[2], lock)
    elseif v[3] then
      ui.tile(v[1], v[2], v[3], ui_index, lock )
    end
  end
end


local function tile_x(x)
  return 21 * (x) + 1 
end

local function wpos(x) return util.linlin(0, #ui.waveform, 0, 121, x) end

function ui.draw_save_icon(x, y, index, ui_index, slot)
  screen.rect(x + 5, y + 3, 12, 12)
  screen.stroke()
  
  set_brightness(index, ui_index)
  

  screen.rect( x + 16, y + 2,1,1)
  screen.fill()

  screen.level(0)  
  screen.rect( x + 7, y + 3,8,4)
  screen.stroke()
  
  screen.rect( x + 11, y + 3,2,2)
  screen.fill()
  
  screen.move( x + 10, y + 13)
  screen.text_center(slot)
  screen.stroke()
end


function ui.sampling(sampler, ui_index, pos) 
  local modes = {'ST', 'L+R', 'L', 'R'}
  local sources = {'EXT', 'INT' } 
  -- vus[sampling.mode][sampling.source]
  local vus  = { {{ui.in_l, ui.in_r },{ui.out_l, ui.out_r }},
                 {{(ui.in_l+ui.in_r)/((ui.in_l > 0 or ui.in_r > 0) and 2 or 1 )},{(ui.out_l+ui.out_r)/((ui.out_l > 0 or ui.out_r > 0) and 2 or 1)}},
                 {{ui.in_l},{ui.out_l}},
                 {{ui.in_r},{ui.out_r}},
  }
  local src = sources[sampler.source]
  local mode = modes[sampler.mode] 
  --local pos = sampler.pos
  local rec = sampler.rec 
  local play = sampler.play 

  local len = sampler.length
  
  set_brightness(-1, ui_index)
  
  screen.rect(tile_x(0), 8,  20, 17)
  screen.fill()
  screen.level(0) 
  if sampler.mode == 1 then
      screen.rect(5,11,13, 2)
      screen.rect(5,13,13, 2)
      screen.stroke()
      screen.level(0)
      screen.rect(5, 11, vus[sampler.mode][sampler.source][1], 1)
      screen.rect(5, 13, vus[sampler.mode][sampler.source][2], 1)
  else
      screen.rect(5,11,13, 4)
      screen.stroke()
      screen.rect(5, 11, vus[sampler.mode][sampler.source][1], 4)
      screen.fill()
  end
  
  screen.fill()
  screen.level(0)
  screen.move( tile_x(0)  + 10, 8 + 15)
  screen.text_center(mode)

  set_brightness(0, ui_index)
  screen.rect(tile_x(1) , 8,  20, 17)
  screen.fill()
  screen.level(0) 
  screen.move( tile_x(1)  + 10, 8 + 7)
  screen.text_center('SRC')
  screen.move( tile_x(1) + 10, 8 + 15)
  screen.text_center(src)


  set_brightness(1, ui_index)
  if rec  then screen.level(15) end
  screen.rect( tile_x(2) , 8,  20, 17)
  screen.fill()
  

  screen.level(0) 
  screen.circle( tile_x(2)  + 10, 8 + 9, 4.5)
  
  if rec then
    screen.circle( tile_x(2)  + 10, 8 + 9, 5)
    screen.fill() 
  else 
    screen.circle( tile_x(2)  + 10, 8 + 9, 4.5)
    screen.stroke() 
  end

  set_brightness(2, ui_index)
  screen.rect( tile_x(3) , 8,  20, 17)
  screen.fill()
  screen.level(0) 
  
  screen.move(tile_x(3) + 7, 8 + 5)
  screen.line(tile_x(3) + 7 + 8, 8 + 5 + (8 * 0.5))
  screen.line(tile_x(3) + 7, 8 + 13)
  screen.close()
  if rec then screen.fill() 
  else screen.stroke() end

  screen.line_width(1)
  set_brightness(3, ui_index)
  screen.rect( tile_x(4) , 8,  20, 17)
  screen.fill()
  screen.level(0) 
  
  
  ui.draw_save_icon(tile_x(4), 8, 3, ui_index, sampler.slot)
  
  set_brightness(4, ui_index)
  screen.rect( tile_x(5) , 8,  20, 17)
  screen.fill()
  screen.level(0)
  
  screen.move( tile_x(5) + 10, 8 + 15)
  screen.rect(tile_x(5) + 7, 8 + 7, 8, 8)
  screen.rect(tile_x(5) + 6, 8 + 5, 10, 2)
  
  screen.stroke()

  screen.rect(tile_x(5) + 9, 8 + 3, 1, 1)
  screen.rect(tile_x(5) + 10, 8 + 2, 1, 1)
  screen.rect(tile_x(5) + 11, 8 + 3, 1, 1)
  
  screen.rect(tile_x(5) + 8, 8 + 8, 1, 5)
  screen.rect(tile_x(5) + 10, 8 + 8, 1, 5)
  screen.rect(tile_x(5) + 12, 8 + 8, 1, 5)
  screen.fill()

  screen.level(2)
  screen.rect(2, 27, 124 , 34 )
  screen.stroke()
  
  screen.level(2)
  screen.stroke()
 

  if rec then
    local p = math.floor(pos * 10)
    ui.waveform[p] = sampler.source == 1 and { ui.in_l, ui.in_r } or { ui.out_l, ui.out_r }
  end
  
  screen.level(1)
  

  for k,v in pairs(ui.waveform) do

    local l = sampler.mode == 1 and 1 or sampler.mode == 4 and 2 or 1
    local r = sampler.mode == 1 and 2 or sampler.mode == 3 and 1 or 2 

    screen.move(3 + wpos(k) , 44)
    screen.line(3 + wpos(k) , 43 - util.clamp((ui.waveform[k][l]),0, 15))
    screen.stroke()

    screen.move(3 + wpos(k) , 43)
    screen.line(3  +wpos(k), 44 + util.clamp((ui.waveform[k][r]),0, 15))
    screen.stroke()
  end

  if play then
    screen.level(2)
    local pos_ = util.linlin(0,sampler.rec_length, 3, 123, pos)
    screen.move( pos_, 60)
    screen.line( pos_, 27)
    screen.stroke()
  end
  
  set_brightness(5, ui_index)
  local start_ = util.linlin( 0,sampler.rec_length, 0, 122, sampler.start)
  screen.move(3 + start_, 60)
  screen.line(3 + start_, 27)
  
  screen.stroke()

  set_brightness(6, ui_index)
  local end_ = util.linlin(0, sampler.rec_length, 0, 122, sampler.length)
  screen.move( 3 + end_, 60)
  screen.line( 3 + end_, 27)
  
  screen.stroke()
end


function ui.draw_reverb(x, y, index, stage)
    local w, h = 40, 34
    
    screen.level(2)
    screen.rect(x, y + 8, w, h - 8)
    screen.stroke()

    screen.level((index == 10 or index == 11) and 6 or 2)
    screen.rect(x - 1, y - 1, w + 1, 7)
    screen.fill()

    local time = util.round(util.linlin(0.1, 60, 0, 2, params:get('reverb_time')))
    local size = util.round(util.linlin(0, 5, 2, 15, params:get('reverb_size')))
    local damp = util.round(util.linlin(0, 1, 1, util.round(size - 1), params:get('reverb_damp')))
    local diff = util.round(util.linlin(0, 1, 1, 3, params:get('reverb_diff')))
    --local mod_depth = util.linlin(0, 1, 10, 40, params:get('reverb_moddepth'))
    --local mod_freq = util.linlin(0, 1, 20, 34, params:get('reverb_modfreq'))
    --local lowcut = util.round(util.linlin(100, 6000, 6, util.round(size), params:get('reverb_lowcut'))) - size
    --local highcut = util.round( util.linlin(1000, 10000, 0, util.round(size - 6 )  , params:get('reverb_highcut')))

    screen.level(0)
    screen.move(x + 19, y + 5)
    if  index > 9  and index < 12 then
      local n = {[10] = "DAMP", [11] = "DIFF"} -- , [12] = 'LOWCUT', [13] = 'HIGHCUT',}   --[[[11] = 'MOD DEPTH', [12] = 'MOD FREQ',]] 
      screen.text_center(n[index])
    else
      screen.text_center('REVERB')
    end

    ui.reverb.velocity = util.linlin(0, 1, 0.01, ( time / 5) / (1 / 2), 0.15)
    ui.reverb.position = (ui.reverb.position - ui.reverb.velocity) % (math.pi * (2 / (diff/2)))
    ui.reverb.x =  ((ui.reverb.orbit) * (size/(16))) * math.sin(ui.reverb.position / (size - damp)/2)
    ui.reverb.y = ((ui.reverb.orbit) * (size/16)) * math.sin(ui.reverb.position / (size - damp)/2)

    screen.level(1)
    local s_x = util.round(size, 1) 
    local s_y = s_x 
    local h_x = util.round(s_x / 2,1) 

    local cube_x = util.round((x + 17) - h_x) --+ util.round(ui.reverb.x / 4)  
    local cube_y = util.round((y + 25) - h_x)

    screen.rect(cube_x + h_x  , cube_y - h_x , s_x , s_y )   
    screen.stroke()

    screen.level(1)
    screen.move(cube_x,cube_y - 1 + s_y)
    screen.line(cube_x+h_x, cube_y - h_x - 1 + s_y)
    screen.stroke()
  
    screen.move(cube_x  + s_x,cube_y - 1 + s_y)
    screen.line(cube_x+h_x + s_x, cube_y - h_x - 1 + s_y)
    screen.stroke()
  
    screen.level(index == 11 and 15 or 2) -- index > 9 and index < 14 and i or i % 4 )
    screen.circle(x + (w/2) + (ui.reverb.x  / (16 - size)) , y + (h/1.5) - (ui.reverb.y / (16 - size)), 2 - (ui.reverb.x/10) + diff )
    screen.fill()
  
    if index == 10 then 
    
      screen.level(15)
      screen.move(cube_x + s_x - 1, cube_y - damp + s_x)
      screen.line(cube_x - 1, cube_y - damp + s_x)

      screen.line(cube_x - 1, cube_y - damp + s_x)

      screen.line(cube_x + h_x - 1, cube_y - damp + s_x - h_x)
      screen.line(cube_x + h_x + s_x - 1, cube_y - h_x - damp + s_x) 

      screen.close()
      screen.stroke()
    end
--[[    elseif index == 11 then

      screen.level(15)
      screen.move(cube_x + s_x - 1, cube_y - diff + s_x)
      screen.line(cube_x - 1, cube_y - diff + s_x)

      screen.line(cube_x - 1, cube_y - diff + s_x)

      screen.line(cube_x + h_x - 1, cube_y - diff + s_x - h_x)
      screen.line(cube_x + h_x + s_x - 1, cube_y - h_x - diff + s_x) 

      screen.close()
      screen.stroke()
]]  
  
  
  
  screen.level(1)
  screen.move(cube_x,cube_y - 1)
  screen.line(cube_x+s_x/2, cube_y - s_y/2 - 1)
  screen.stroke()

  screen.move(cube_x  + s_x,cube_y - 1)
  screen.line(cube_x+s_x/2 + s_x, cube_y - s_y/2 - 1)
  screen.stroke()

  screen.level(1)
  screen.rect(cube_x, cube_y, s_x, s_y )
  screen.stroke()

  screen.level(0)
  screen.rect(x,y + h - 2, w - 2, 1)
  screen.fill()

  --screen.level(2)
  --screen.rect(x, y, w, h)
  --screen.stroke()


end

function ui.draw_comp(x, y, index)
  local w, h = 40, 34
  
  screen.level(2)
  screen.rect(x, y + 8, w, h - 8)
  screen.stroke()
  screen.level(index > 2 and index < 8 and 6 or 2)
  screen.rect(x - 1, y - 1, w + 1, 7)
  screen.fill()

  local level = util.linlin(-99, 6, 0, 34, params:get('comp_level'))
  local threshold = util.linexp(0, 1, 5, 15, params:get('comp_threshold'))
  local slope_b = util.linlin(0, 1, 0, 10, params:get('comp_slopebelow'))
  local slope_a = util.linlin(0, 1, 0, 10, params:get('comp_slopeabove'))
  local attack = util.linlin(0, 1, 3, 20, params:get('comp_clamptime'))
  local release = util.linlin(0, 1, 3, 39, params:get('comp_relaxtime'))

  screen.level(0)
  screen.move(x + 19, y + 5)
  if (index > 0 and index < 8)  then
    local n = {[1] = "COMP VOL", [2] = "DRY/WET", [3] = 'THRESH', [4] = 'SLOPE B', [5] = 'SLOPE A', [6] = 'ATTACK', [7] = 'RELEASE'}
    screen.text_center(n[index])
  else
    screen.text_center('DYNAMICS')
  end
  
  screen.stroke()
  screen.level(index == 6 and 15 or 1)
  screen.move(x, y + h - slope_a)
  screen.line(x + attack, y + h - threshold - slope_a)
  screen.stroke()
  screen.level(index == 4 and 15 or 1)
  screen.move(x + attack, y + h - threshold - slope_a)
  screen.line(x + w - 1 , y + h - threshold - slope_b)
  screen.stroke()
  if index == 5 then
    screen.level(index == 5 and 15 or 1)
    screen.rect( x + attack - 1, y + h - threshold - slope_a -1, 3, 3)
    screen.fill()
  end
  
  screen.level(index == 7 and 15 or 1)
  screen.move(x + release, y + h - threshold - 10)
  screen.line(x + release, y + h - 1)
  screen.stroke()
  --thr

  screen.level(index == 3 and 15 or 1)
  screen.move(x +  release , y + h - threshold - 10)
  screen.line(x   , y + h - threshold - 10)
  screen.stroke()
  screen.level(1)
  screen.rect(x + w - 3, y + h - 1 , 1,   - ui.out_l)
  screen.rect(x + w - 2, y + h - 1, 1,  - ui.out_r)
  screen.fill()
end

function ui.draw_lfo_tile(x,y, index)
  
  local shapes = {'SIN', 'TRI', 'SAW', 'SQR', 'RND'}
  local shape1 = params:get('lfo_1_wave_shape')
  local freq1 = params:get('lfo_1_freq')
  local shape2 = params:get('lfo_2_wave_shape')
  local freq2 = params:get('lfo_2_freq')
 -- print(freq1,freq2,shape1,shape2)
--  2.0	4.0	1	4


  local lvl = (index > 14 and index < 19) and 6 or 2
  screen.level(lvl)
  screen.rect(x,  y, 20, 17)
  screen.fill()
  screen.level(2)
  screen.rect(x + 22, y + 1, 40, 16)
  screen.stroke()

  screen.level(0)
  screen.move(x + 10, y + 7)
  
  if  (index > 14 and index < 19) then
    local n = {[15] = "FREQ", [16] = "SHP", [17] = "FREQ", [18] = "SHP",} 
    screen.text_center(n[index])
  else
    screen.text_center('LFO')
  end



  local lvl2 = (index > 14 and index < 19) and index or 15

 -- local n = index == 16 and 'shape1' or 'shape2'
  local t = index == 17 and freq1 or freq2

  --if (index == 16 or index == 18 )then 
    --screen.move(x + 9, y + 8)
    --screen.text_center(shapes[n] )
    --screen.stroke()
  if index == 15 then
    ui.draw_level_meter(x, y, 0.05, 20, freq1, 15, index)
  elseif index == 16 then
    screen.move(x + 10, y + 15)
    screen.text_center(shapes[shape1] )
    screen.stroke()
  elseif index == 17 then
    ui.draw_level_meter(x, y, 0.05, 20, freq2, 17, index)
  elseif index == 18 then
    screen.move(x + 10, y + 15)
    screen.text_center(shapes[shape2] )
    screen.stroke()
  else
    ui.draw_level_meter(x, y, 0.05, 20, freq1, 15, index)
  end

  screen.level((index == 15 or index == 16) and 6 or 1)
  lfo(x + 17, y, 1, util.clamp(freq1,0.2,20), shape1, 1, 38)
  screen.level((index == 17 or index == 18) and 6 or 1)
  lfo(x + 17, y + 8, 2, util.clamp(freq2,0.2, 20), shape2, 1, 38)
end

function ui.patterns(pattern, metaseq, ui_index, stage)
  local tile = { 

    {1, 'VOL', function(i,n) ui.draw_level_meter(1, 8, -99, 6,    params:get('comp_level'), i,  ui_index, false, n) end},
    {2, 'MIX', function(i,n) ui.draw_level_meter(1, 26, -1, 1,    params:get('comp_mix'), 2, ui_index, false, n)    end},
    {4, 'TIME', function(i,n) ui.draw_level_meter(64, 8, 0.1, 60, params:get('reverb_time'), 8,  ui_index, false, n) end},
    {10,'SIZE', function(i,n) ui.draw_level_meter(64, 26, 0, 5,   params:get('reverb_size'), 9,  ui_index, false, n) end},

}

for k, v in pairs(tile) do
        
  
if v[3] and type(v[3]) == 'function' then
  v[3](v[1], v[2])
elseif v[3] then
  ui.tile(v[1], v[2], v[3], ui_index, lock )
end
end

ui.draw_comp(23, 9, ui_index)
ui.draw_reverb(86, 9, ui_index, stage)
ui.draw_delay(1, 44, ui_index)
ui.draw_lfo_tile(64, 44, ui_index)

end

return ui