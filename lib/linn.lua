--  
--   ////\\\\
--   ////\\\\  LINN
--   ////\\\\  BY NEAUOIRE
--   \\\\////
--   \\\\////  LINN LAYOUT
--   \\\\////
--
-- converted into lib 
local linn = {}


local keys_down = 0
local midi_signal_out
local focus = { x = 0, y = 0 }
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

function linn.init()
  linn.connect()
  -- Render Style
  screen.level(15)
  screen.aa(0)
  screen.line_width(1)
  -- Render
  linn.grid_redraw()
end

function linn.connect()
  g = grid.connect()
  g.key = linn.grid_key
  midi_signal_out = midi.connect(1)
end

function linn.note_at(i)
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

function linn.pos_at(id)
  return { x = ((id-1) % 16) + 1, y = math.floor(id / 16) + 1 }
end

function linn.id_at(x,y)
  return ((y-1) * 16) + x
end

function linn.on_grid_key_down(x,y)
  focus.x = x
  focus.y = y
  --midi_signal_out:note_on(note_at(id_at(x,y)).v,127)
  keys_down = keys_down + 1
  --return note_at(id_at(x,y)).v, 127
end

function linn.on_grid_key_up(x,y)
  focus.x = 0
  focus.y = 0
  --midi_signal_out:note_off(note_at(id_at(x,y)).v,127)
  keys_down = keys_down - 1
end


function linn.grid_key(x,y,z)
  if y < 8 then
    if z == 1 then
      linn.on_grid_key_down(x,y)
  
      --print(linn.note_at(linn.id_at(x,y)).v)
      return linn.note_at(linn.id_at(x,y)).v
    else
      linn.on_grid_key_up(x,y)
    end
  end
  --linn.grid_redraw()
end

function linn.grid_redraw(g)
  --g:all(0)
  for i=1,111 do 
    pos = linn.pos_at(i)  
    note = linn.note_at(i)
    g:led(pos.x,pos.y,note.l)
  end
  g:led(focus.x,focus.y, 10)
  --g:refresh()
end


return linn