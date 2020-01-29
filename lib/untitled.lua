--  
--   ////\\\\
--   ////\\\\  LINN
--   ////\\\\  BY NEAUOIRE
--   \\\\////
--   \\\\////  LINN LAYOUT
--   \\\\////
--

local g
local viewport = { width = 128, height = 64, frame = 0 }
local focus = { x = 1, y = 1, brightness = 15 }
local chan = 1
local keys_down = 0
local midi_signal_out
local keys = { 'C','C#','D','D#','E','F','F#','G','G#','A','A#','B' }

local notes = {
  'F3', 'F3#', 'G3', 'G3#', 'A3', 'A3#', 'B3', 'C4', 'C4#', 'D4', 'D4#', 'E4', 'F4', 'F4#', 'G4', 'G4#',
  'C3', 'C3#', 'D3', 'D3#', 'E3', 'F3', 'F3#', 'G3', 'G3#', 'A3', 'A3#', 'B3', 'C4', 'C4#', 'D4', 'D4#',
  'G2', 'G2#', 'A2', 'A2#', 'B2', 'C3', 'C3#', 'D3', 'D3#', 'E3', 'F3', 'F3#', 'G3', 'G3#', 'A3', 'A3#',
  'D2', 'D2#', 'E2', 'F2', 'F2#', 'G2', 'G2#', 'A2', 'A2#', 'B2', 'C3', 'C3#', 'D3', 'D3#', 'E3', 'F3',
  'A1', 'A1#', 'B1', 'C3', 'C2#', 'D2', 'D2#', 'E2', 'F2', 'F2#', 'G2', 'G2#', 'A2', 'A2#', 'B2', 'C3',
  'E1', 'F1', 'F1#', 'G1', 'G1#', 'A1', 'A1#', 'B1', 'C2', 'C2#', 'D2', 'D2#', 'E2', 'F2', 'F2#', 'G2',
  'B0', 'C1', 'C1#', 'D1', 'D1#', 'E1', 'F1', 'F1#', 'G1', 'G1#', 'A1', 'A1#', 'B1', 'C2', 'C2#', 'D2',
  'F0#', 'G0', 'G0#', 'A0', 'A0#', 'B0', 'C1', 'C1#', 'D1', 'D1#', 'E1', 'F1', 'F1#', 'G1', 'G1#', 'A1',
}


local index_of = function(list,value)
  for i=1,#list do
    if list[i] == value then return i end
  end
  return -1
end

-- Main

function init()
  connect()
  -- Render Style
  screen.level(15)
  screen.aa(0)
  screen.line_width(1)
  -- Render
  update()
end

function connect()
  g = grid.connect()
  g.key = on_grid_key
  midi_signal_out = midi.connect(1)
end

function is_connected()
  return g.device ~= nil
end

function note_at(i)
  local n = notes[i]
  local k = n:sub(1, 1)
  local o = tonumber(n:sub(2, 2))
  local s = n:match('#')
  local p = n:gsub(o,'')
  local v = index_of(keys,p) + (12 * (o+2)) - 1
  local l = 0

  if p == 'C' then
    l = 15
  elseif s then
    l = 0
  else
    l = 5
  end

  return { i = i, k = k, o = o, s = s, v = v, l = l, p = p }
end

function pos_at(id)
  return { x = ((id-1) % 16) + 1, y = math.floor(id / 16) + 1 }
end

function id_at(x,y)
  return ((y-1) * 16) + x
end

function on_grid_key(x,y,z)
  if z == 1 then
    on_grid_key_down(x,y)
  else
    on_grid_key_up(x,y)
  end

  update()
end

function on_grid_key_down(x,y)
  focus.x = x
  focus.y = y
  midi_signal_out:note_on(note_at(id_at(x,y)).v,127)
  keys_down = keys_down + 1
end

function on_grid_key_up(x,y)
  midi_signal_out:note_off(note_at(id_at(x,y)).v,127)
  keys_down = keys_down - 1
end

function update()
  g:all(0)
  for i=1,128 do 
    pos = pos_at(i)  
    note = note_at(i)
    g:led(pos.x,pos.y,note.l)
  end
  g:led(focus.x,focus.y,10)
  g:refresh()
  redraw()
end

-- Interactions

function key(id,state)
  if id == 2 and state == 1 then
    focus.brightness = 15
  elseif id == 3 and state == 1 then
    focus.brightness = 5
  end
  update()
end

function enc(id,delta)
  if id == 2 then
    focus.x = clamp(focus.x + delta, 1, 16)
  elseif id == 3 then
    focus.y = clamp(focus.y + delta, 1, 8)
  end
  update()
end

-- Render

function draw_pixel(x,y)
  if focus.x == x and focus.y == y then
    screen.fill()
    screen.level(15)
  end
  screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
  if focus.x == x and focus.y == y then
    screen.fill()
    screen.level(1)
  end
end

function draw_grid()
  if is_connected() ~= true then return end
  screen.level(1)
  offset = { x = 30, y = 13, spacing = 4 }
  for x=1,16,1 do 
    for y=1,8,1 do 
      draw_pixel(x,y)
    end
  end
  screen.fill()
end

function draw_label()
  if keys_down < 1 then return end

  note = note_at(id_at(focus.x,focus.y))

  screen.level(15)
  local line_height = 8
  screen.move(34,56)
  screen.text(note.p..''..note.o..' '..note.v)
  screen.move(94,56)
  screen.text_right('CHAN'..chan)
  screen.stroke()
end

function redraw()
  screen.clear()
  if is_connected() ~= true then
    screen.move(5,10)
    screen.text('Grid is not connected.')
    screen.fill()
  else
    draw_grid()
    draw_label()
  end
  screen.update()
end

-- Utils

function clamp(val,min,max)
  return val < min and min or val > max and max or val
end