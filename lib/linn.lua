--  
--   ////\\\\
--   ////\\\\  LINN
--   ////\\\\  BY NEAUOIRE
--   \\\\////
--   \\\\////  LINN LAYOUT
--   \\\\////
--
-- lib

local linn = {}


local focus = { x = 0, y = 0 }
local keys = { 'C','C#','D','D#','E','F','F#','G','G#','A','A#','B' }

local notes = {
  'F4', 'F4#', 'G4', 'G4#', 'A4', 'A4#', 'B4', 'C5', 'C5#', 'D5', 'D5#', 'E5', 'F5', 'F5#', 'G5', 'G5#',
  'C4', 'C4#', 'D4', 'D4#', 'E4', 'F4', 'F4#', 'G4', 'G4#', 'A4', 'A4#', 'B4', 'C5', 'C5#', 'D5', 'D5#',
  'G3', 'G3#', 'A3', 'A3#', 'B3', 'C4', 'C4#', 'D4', 'D4#', 'E4', 'F4', 'F4#', 'G4', 'G4#', 'A4', 'A4#',
  'D3', 'D3#', 'E3', 'F3', 'F3#', 'G3', 'G3#', 'A3', 'A3#', 'B3', 'C4', 'C4#', 'D4', 'D4#', 'E4', 'F4',
  'A2', 'A2#', 'B2', 'C4', 'C3#', 'D3', 'D3#', 'E3', 'F3', 'F3#', 'G3', 'G3#', 'A3', 'A3#', 'B3', 'C4',
  'E2', 'F2', 'F2#', 'G2', 'G2#', 'A2', 'A2#', 'B2', 'C3', 'C3#', 'D3', 'D3#', 'E3', 'F3', 'F3#', 'G3',
  'B1', 'C2', 'C2#', 'D2', 'D2#', 'E2', 'F2', 'F2#', 'G2', 'G2#', 'A2', 'A2#', 'B2', 'C3', 'C3#', 'D3',
  'F1#', 'G1', 'G1#', 'A1', 'A1#', 'B1', 'C2', 'C2#', 'D2', 'D2#', 'E2', 'F2', 'F2#', 'G2', 'G2#', 'A2',
}


local index_of = function(list,value)
  for i=1,#list do
    if list[i] == value then return i end
  end
  return -1
end

-- Main

function linn.note_at(i)
  local n = notes[i]
  local k = n:sub(1, 1)
  local o = tonumber(n:sub(2, 2))
  local s = n:match('#')
  local p = n:gsub(o,'')
  local v = index_of(keys, p) + (12 * (o + 2)) - 1
  local l = 0

  if p == 'C' then
    l = 15
  elseif s then
    l = 2
  else
    l = 6
  end

  return { i = i, k = k, o = o, s = s, v = v, l = l, p = p }
end

function linn.pos_at(id)
  return { x = ((id-1) % 16) + 1, y = math.floor(id / 16) + 1 }
end

function linn.id_at(x,y)
  return ((y-1) * 16) + x
end


function linn.on_grid_key_down(x,y, m)
  focus.x = x
  focus.y = y
  if m then m:note_on(linn.note_at(linn.id_at(x,y)).v,127) end
end

function linn.on_grid_key_up(x,y, m)
  focus.x = 0
  focus.y = 0
  if m then m:note_off(linn.note_at(linn.id_at(x,y)).v,127) end
end


function linn.grid_key(x, y, z, m)--, tr, sample)
  if y < 8 then
    if z == 1 then
      linn.on_grid_key_down(x, y, m)
    else
      linn.on_grid_key_up(x, y, m)
      return false
    end
    return linn.note_at(linn.id_at(x,y)).v
  end
end

function linn.grid_redraw(g)
  for i=1, 111 do 
    pos = linn.pos_at(i)  
    note = linn.note_at(i)
    g:led(pos.x,pos.y, note.l)
  end
  g:led(focus.x,focus.y, 10)
  g:led(16,1,3) 
end


return linn