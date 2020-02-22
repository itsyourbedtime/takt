local fs = {}
-- fileselect mod


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
  if (fs.path and fs.callback) then fs.callback(fs.sample_id, fs.path) params:set('play_mode_' .. fs.sample_id, 2) end
  fs.open = false
  engine.noteOff(100)
end


fs.getdir = function()
  local path = fs.folder
  for k,v in pairs(fs.folders) do
    path = path .. v
  end
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
    local max_line_length = 76
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
            fs.preview = true
            params:set("sample_100", fs.path)
            -- small delay to get it all working
            local m  = metro.init()
            m.time = 0.3
            m.count = 1
            m.event = function()
                engine.playMode(100, 2)
                engine.noteOn(100, 261.6, 0.7, 100 )
            end
            m:start()
        end
    elseif z == 0 then
        engine.noteOff(100)
        fs.preview = false
    end
end

fs.key = function(n,z)
  if n == 1 then
    fs.preview_sample(z)
  elseif n==2 and z==1 then
    if fs.depth > 0 then
      fs.folders[fs.depth] = nil
      fs.depth = fs.depth - 1
      fs.getlist()
    else
      fs.path = nil
      fs.exit()
    end
    -- select
  elseif n==3 and z==1 then
    if #fs.list > 0 then
      fs.file = fs.list[fs.pos+1]
      if string.find(fs.file,'/') then
        fs.depth = fs.depth + 1
        fs.folders[fs.depth] = fs.file
        fs.getlist()
      else
        local path = fs.folder
        for k,v in pairs(fs.folders) do
          path = path .. v
        end
        fs.path = path .. fs.file
        fs.done = true
      end
    end
  
  elseif z == 0 and fs.done == true then
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
  end
end


fs.redraw = function()
    
    screen.level(0)
    screen.rect(43, 8, 83, 53)
    screen.fill()
    screen.level(2)
    screen.rect(44, 9, 82, 52)
    screen.stroke()


    if #fs.list == 0 then
        screen.level(4)
        screen.move(45, 15)
        screen.text("(no files)")
    else
        for i= 1, fs.bounds_y do 
            local list_index = i + (fs.s_offset)

            screen.level(4)
            screen.move(46, 8 + 8 * i )
            screen.level(fs.pos + 1 == list_index and 9 or 2)
            screen.text(fs.display_list[list_index] or '')
            screen.stroke()
        end
        if #fs.list > 6 then 
            screen.level(1)
            screen.rect(123, 10 + (fs.pos), 1, 50 - #fs.list)
            screen.fill()
        end
    end
end


return fs