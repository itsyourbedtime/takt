local fs = {}



-- fileselect utility
-- reroutes redraw/enc/key


function fs.enter(folder, callback, id)
  fs.s_offset = 0
  fs.bounds_y = 6
  fs.open = true
  fs.folders = {}
  fs.list = {}
  fs.display_list = {}
  fs.lengths = {}
  fs.pos = 0
  fs.depth = 0
  fs.folder = folder
  fs.callback = callback
  fs.done = false
  fs.path = nil
  fs.sample_id = id 

  
  if fs.folder:sub(-1,-1) ~= "/" then
    fs.folder = fs.folder .. "/"
  end

  fs.getlist()

end

function fs.exit()
  if (fs.path and fs.callback) then fs.callback(fs.sample_id, fs.path) end
  --else fs.callback("cancel") end
  fs.open = false
  engine.noteOff(100)
end


fs.getdir = function()
  local path = fs.folder
  for k,v in pairs(fs.folders) do
    path = path .. v
  end
  --print("path: "..path)
  return path
end

fs.getlist = function()
  local dir = fs.getdir()
  fs.list = util.scandir(dir)
  fs.display_list = {}
  fs.lengths = {}
  fs.len = #fs.list
  fs.pos = 0
  fs.s_offset = 0

  -- Generate display list and lengths
  for k, v in ipairs(fs.list) do
    local line = v
    local max_line_length = 80

    line = util.trim_string_to_width(line, max_line_length)
    fs.display_list[k] = line
  end
end

fs.preview_sample = function(z)
    if z == 1 then
        fs.file = fs.list[fs.pos+1]
        if string.find(fs.file,'/') then
            print('cant play folder')
        else
            local path = fs.folder
            for k,v in pairs(fs.folders) do
            path = path .. v
            end
            fs.path = path .. fs.file

            params:set("sample_100", fs.path)
            -- small delay to get it all working
            local m  = metro.init()
            m.time = 0.3
            m.count = 1
            m.event = function()
                engine.playMode(100, 2)
                engine.noteOn(100, 261.6, 1, 100 )
            end
            m:start()
        end
    elseif z == 0 then
        engine.noteOff(100)

    end
end

fs.key = function(n,z)
  if n == 1 then
    fs.preview_sample(z)
    -- back
  elseif n==2 and z==1 then
    if fs.depth > 0 then
      --print('back')
      fs.folders[fs.depth] = nil
      fs.depth = fs.depth - 1
      fs.getlist()
    --fs.redraw()
    else
      fs.exit()
      fs.done = true
    end
    -- select
  elseif n==3 and z==1 then
    if #fs.list > 0 then
      fs.file = fs.list[fs.pos+1]
      if string.find(fs.file,'/') then
        --print("folder")
        fs.depth = fs.depth + 1
        fs.folders[fs.depth] = fs.file
        fs.getlist()
        --fs.redraw()
      else
        local path = fs.folder
        for k,v in pairs(fs.folders) do
          path = path .. v
        end
        fs.path = path .. fs.file
        fs.done = true
      end
    end
  end
  if z == 0 and fs.done == true then
    fs.exit()
  end
end

fs.update_offset = function(val, y, length, bounds, offset)
    if y  > val + (8 - offset)  then
      val = util.clamp( val + 1, 0, length - bounds)
    elseif y < bounds + ( val - (7 - offset))  then
      val = util.clamp( val - 1, 0, length - bounds)
    end
    return val
  end
  
  

fs.enc = function(n,d)
  if n==2 then
    fs.pos = util.clamp(fs.pos + d, 0, fs.len - 1)
    fs.s_offset = fs.update_offset(fs.s_offset, fs.pos+1, fs.len, fs.bounds_y, 2)
    print(fs.s_offset, fs.len, fs.pos )
    --fs.redraw()
  end
end


fs.redraw = function()
  if #fs.list == 0 then
    screen.level(4)
    screen.move(45, 15)
    screen.text("(no files)")
  else
--[[    for i=1,6 do
      if (i > 2 - fs.pos) and (i < fs.len - fs.pos + 3) then
        local list_index = i+fs.pos-2
        screen.move(46, 8 +  8 * i)
        if(i==3) then
          screen.level(9)
        else
          screen.level(2)
        end
        screen.text(fs.display_list[list_index])

        end
    end
]]  

for i= 1, fs.bounds_y do 

    screen.level(4)
    screen.move(46, 8 + 8 * i )
    local list_index = i + (fs.s_offset)
    
    if( fs.pos + 1  == list_index ) then
        screen.level(9)
      else
        screen.level(2)
      end
    screen.text(fs.display_list[list_index] or '')

    screen.stroke()
  end




end
  ---screen.update()
end


return fs