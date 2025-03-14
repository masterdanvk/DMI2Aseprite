--[[
  Simple DMI Editor with Local Storage
  
  Uses a simple local file to store metadata between runs.
]]

-- Global storage
local rawZtxtChunk = nil
local debugMode = false

-- Debug message function
function dbgMsg(msg)
  if debugMode then
    app.alert("DEBUG: " .. msg)
  end
end

-- Converts bytes to hex string for debugging
function bytesToHex(bytes, maxLen)
  local result = ""
  maxLen = maxLen or #bytes
  for i = 1, math.min(maxLen, #bytes) do
    result = result .. string.format("%02X ", string.byte(bytes, i))
    if i % 16 == 0 then result = result .. "\n" end
  end
  return result
end

-- Load metadata from a file
function loadMetadataFromFile(filename)
  local file = io.open(filename, "rb")
  if not file then
    return nil
  end
  
  local data = file:read("*all")
  file:close()
  
  if #data > 0 then
    dbgMsg("Loaded " .. #data .. " bytes from " .. filename)
    return data
  end
  
  return nil
end

-- Save metadata to a file
function saveMetadataToFile(data, filename)
  local file = io.open(filename, "wb")
  if not file then
    return false
  end
  
  file:write(data)
  file:close()
  
  dbgMsg("Saved " .. #data .. " bytes to " .. filename)
  return true
end

-- A safer alternative to os.remove
function safeRemoveFile(filename)
  -- Try to open the file in write mode with truncation
  local file = io.open(filename, "w")
  if file then
    file:close()
    dbgMsg("Emptied file: " .. filename)
    return true
  end
  return false
end

-- Mirror East to West sprites
function mirrorEastToWest()
  -- Check if sprite is open
  if not app.activeSprite then
    app.alert("No sprite open to process")
    return
  end
  
  local sprite = app.activeSprite
  local width = sprite.width
  local height = sprite.height
  
  -- Get frame size from user or use defaults
  local dlg = Dialog("Frame Size")
  dlg:number{ id = "cellWidth", label = "Frame Width:", text = "32", decimals = 0 }
  dlg:number{ id = "cellHeight", label = "Frame Height:", text = "32", decimals = 0 }
  dlg:button{ id = "ok", text = "OK" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()
  
  if not dlg.data.ok then
    return
  end
  
  local cellWidth = dlg.data.cellWidth
  local cellHeight = dlg.data.cellHeight
  
  -- Ensure sprite dimensions are multiples of the cell size
  if width % cellWidth ~= 0 or height % cellHeight ~= 0 then
    app.alert("Sprite dimensions must be multiples of the frame size")
    return
  end
  
  -- Calculate total number of cells and columns
  local columns = width / cellWidth
  local rows = height / cellHeight
  local totalCells = columns * rows
  
  -- Count how many sprites we'll process
  local totalProcessed = 0
  
  -- Start transaction for undo support
  app.transaction(function()
    -- Get the target frame
    local frameNumber = app.activeFrame.frameNumber
    
    -- Using SNEW pattern (East=2, West=3)
    local eastIndex = 2
    local westIndex = 3
    
    -- Create a new image for the entire sprite
    local fullImage = Image(sprite.width, sprite.height, sprite.colorMode)
    
    -- Make the entire image transparent
    fullImage:clear(app.pixelColor.rgba(0, 0, 0, 0))
    
    -- Draw the current frame of the sprite onto the image
    fullImage:drawSprite(sprite, frameNumber)
    
    -- Use this full-size image for processing
    local modified = false
    
    -- Process all cells
    for row = 0, rows - 1 do
      for col = 0, columns - 1 do
        -- Get the cell index
        local cellIndex = row * columns + col
        
        -- Determine direction based on position in the cycle
        local direction = cellIndex % 4
        
        -- We only care about East cells
        if direction == eastIndex then
          -- Calculate positions
          local eastX = col * cellWidth
          local eastY = row * cellHeight
          
          -- Check if next cell exists and is West
          local nextCellIndex = cellIndex + 1
          if nextCellIndex < totalCells and nextCellIndex % 4 == westIndex then
            local nextCol = nextCellIndex % columns
            local nextRow = math.floor(nextCellIndex / columns)
            local westX = nextCol * cellWidth
            local westY = nextRow * cellHeight
            
            -- Copy the east sprite to a temporary buffer
            local eastImage = Image(cellWidth, cellHeight, sprite.colorMode)
            
            -- Clear the temporary buffer first
            eastImage:clear(app.pixelColor.rgba(0, 0, 0, 0))
            
            -- Copy east sprite pixels to the buffer
            for py = 0, cellHeight - 1 do
              for px = 0, cellWidth - 1 do
                local pixelColor = fullImage:getPixel(eastX + px, eastY + py)
                eastImage:putPixel(px, py, pixelColor)
              end
            end
            
            -- Clear the west area
            for py = 0, cellHeight - 1 do
              for px = 0, cellWidth - 1 do
                fullImage:putPixel(westX + px, westY + py, app.pixelColor.rgba(0, 0, 0, 0))
              end
            end
            
            -- Copy the flipped east image to the west position
            for py = 0, cellHeight - 1 do
              for px = 0, cellWidth - 1 do
                local pixelColor = eastImage:getPixel(px, py)
                fullImage:putPixel(westX + (cellWidth - 1 - px), westY + py, pixelColor)
              end
            end
            
            totalProcessed = totalProcessed + 1
            modified = true
          end
        end
      end
    end
    
    -- If modifications were made, apply them to the sprite
    if modified then
      -- For each visible layer, create or update its cel
      for i, layer in ipairs(sprite.layers) do
        if layer.isVisible then
          -- Make layer editable if needed
          local wasEditable = layer.isEditable
          if not wasEditable then
            layer.isEditable = true
          end
          
          -- Create a new cel with the modified image
          -- This replaces any existing cel
          sprite:newCel(layer, frameNumber, fullImage:clone(), Point(0, 0))
          
          -- Restore editability
          if not wasEditable then
            layer.isEditable = false
          end
          
          -- Only need to modify one layer
          break
        end
      end
      
      -- Refresh the screen to show changes
      app.refresh()
    end
  end)
  
  if totalProcessed > 0 then
    app.alert("Mirrored " .. totalProcessed .. " east-facing sprites to west-facing positions")
  else
    app.alert("No east-facing sprites were found to process")
  end
end

-- Delete all West-facing frames
function deleteWestFrames()
  -- Check if sprite is open
  if not app.activeSprite then
    app.alert("No sprite open to process")
    return
  end
  
  local sprite = app.activeSprite
  local width = sprite.width
  local height = sprite.height
  
  -- Get frame size from user or use defaults
  local dlg = Dialog("Frame Size")
  dlg:number{ id = "cellWidth", label = "Frame Width:", text = "32", decimals = 0 }
  dlg:number{ id = "cellHeight", label = "Frame Height:", text = "32", decimals = 0 }
  dlg:button{ id = "ok", text = "OK" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()
  
  if not dlg.data.ok then
    return
  end
  
  local cellWidth = dlg.data.cellWidth
  local cellHeight = dlg.data.cellHeight
  
  -- Ensure sprite dimensions are multiples of the cell size
  if width % cellWidth ~= 0 or height % cellHeight ~= 0 then
    app.alert("Sprite dimensions must be multiples of the frame size")
    return
  end
  
  -- Calculate total number of cells and columns
  local columns = width / cellWidth
  local rows = height / cellHeight
  local totalCells = columns * rows
  
  -- Count how many west frames we'll delete
  local totalDeleted = 0
  
  -- Start transaction for undo support
  app.transaction(function()
    -- Get the target frame
    local frameNumber = app.activeFrame.frameNumber
    
    -- Using SNEW pattern (West=3)
    local westIndex = 3
    
    -- Create a new image for the entire sprite
    local fullImage = Image(sprite.width, sprite.height, sprite.colorMode)
    
    -- Make the entire image transparent
    fullImage:clear(app.pixelColor.rgba(0, 0, 0, 0))
    
    -- Draw the current frame of the sprite onto the image
    fullImage:drawSprite(sprite, frameNumber)
    
    -- Use this full-size image for processing
    local modified = false
    
    -- Process all cells
    for row = 0, rows - 1 do
      for col = 0, columns - 1 do
        -- Get the cell index
        local cellIndex = row * columns + col
        
        -- Determine direction based on position in the cycle
        local direction = cellIndex % 4
        
        -- We only care about West cells
        if direction == westIndex then
          -- Calculate positions
          local westX = col * cellWidth
          local westY = row * cellHeight
          
          -- Clear the west frame
          for py = 0, cellHeight - 1 do
            for px = 0, cellWidth - 1 do
              fullImage:putPixel(westX + px, westY + py, app.pixelColor.rgba(0, 0, 0, 0))
            end
          end
          
          totalDeleted = totalDeleted + 1
          modified = true
        end
      end
    end
    
    -- If modifications were made, apply them to the sprite
    if modified then
      -- For each visible layer, create or update its cel
      for i, layer in ipairs(sprite.layers) do
        if layer.isVisible then
          -- Make layer editable if needed
          local wasEditable = layer.isEditable
          if not wasEditable then
            layer.isEditable = true
          end
          
          -- Create a new cel with the modified image
          -- This replaces any existing cel
          sprite:newCel(layer, frameNumber, fullImage:clone(), Point(0, 0))
          
          -- Restore editability
          if not wasEditable then
            layer.isEditable = false
          end
          
          -- Only need to modify one layer
          break
        end
      end
      
      -- Refresh the screen to show changes
      app.refresh()
    end
  end)
  
  if totalDeleted > 0 then
    app.alert("Deleted " .. totalDeleted .. " west-facing frames")
  else
    app.alert("No west-facing frames were found to delete")
  end
end

-- Show the main dialog
function showMainDialog()
  -- Try to load previously saved metadata if any
  if rawZtxtChunk == nil then
    rawZtxtChunk = loadMetadataFromFile("dmi_metadata.bin")
  end
  
  local dlg = Dialog("DMI Editor")
  
  dlg:separator{ text = "DMI Operations" }
  
  dlg:button{ 
    id = "import", 
    text = "Import DMI",
    onclick = function()
      dlg:close()
      importDMI()
    end
  }
  
  dlg:button{ 
    id = "export", 
    text = "Export DMI",
    onclick = function()
      dlg:close()
      exportDMI()
    end
  }
  
  dlg:separator{ text = "Sprite Operations" }
  
  dlg:button{
    id = "mirror_east_to_west",
    text = "Mirror East → West",
    onclick = function()
      dlg:close()
      mirrorEastToWest()
      showMainDialog()
    end
  }
  
  dlg:button{
    id = "delete_west",
    text = "Delete All West Frames",
    onclick = function()
      dlg:close()
      deleteWestFrames()
      showMainDialog()
    end
  }
  
  if rawZtxtChunk then
    dlg:separator{ text = "Metadata Status" }
    dlg:label{ text = "✓ DMI metadata is loaded (" .. #rawZtxtChunk .. " bytes)" }
    
    -- Add a view button to see the first bytes of metadata
    dlg:button{
      id = "view_metadata",
      text = "View Raw Metadata (Hex)",
      onclick = function()
        local hexData = bytesToHex(rawZtxtChunk, 200)
        local textData = ""
        
        -- Try to extract any printable text
        for i = 1, math.min(200, #rawZtxtChunk) do
          local byte = string.byte(rawZtxtChunk, i)
          if byte >= 32 and byte <= 126 then
            textData = textData .. string.char(byte)
          else
            textData = textData .. "."
          end
        end
        
        local metadlg = Dialog("DMI Raw Metadata")
        metadlg:label{ text = "Raw Metadata (Hex):" }
        metadlg:entry{ id = "hex", text = hexData, readonly = true, multiline = true, width = 400, height = 150 }
        metadlg:label{ text = "Printable Characters:" }
        metadlg:entry{ id = "text", text = textData, readonly = true, multiline = true, width = 400, height = 150 }
        metadlg:button{ id = "close", text = "Close" }
        metadlg:show()
      end
    }
    
    -- Add option to clear metadata
    dlg:button{
      id = "clear_metadata",
      text = "Clear Metadata",
      onclick = function()
        rawZtxtChunk = nil
        safeRemoveFile("dmi_metadata.bin") -- Use safeRemoveFile instead of os.remove
        dlg:close()
        showMainDialog()
      end
    }
  else
    dlg:separator{ text = "Metadata Status" }
    dlg:label{ text = "✗ No DMI metadata loaded" }
  end
  
  dlg:separator{}
  dlg:check{ id = "debug", text = "Debug Mode", selected = debugMode }
  dlg:button{ id = "close", text = "Close" }
  
  dlg:show()
  
  -- Update debug mode
  if dlg.data.debug ~= nil then
    debugMode = dlg.data.debug
  end
end

-- Import a DMI file
function importDMI()
  local dlg = Dialog("Import DMI File")
  dlg:file{
    id = "file",
    label = "Select DMI File:",
    filetypes = {"dmi", "png"},
    open = true
  }
  dlg:button{ id = "ok", text = "OK" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()
  
  if dlg.data.ok and dlg.data.file ~= "" then
    local filename = dlg.data.file
    dbgMsg("Opening file: " .. filename)
    
    -- Read the file directly as binary
    local file = io.open(filename, "rb")
    if not file then
      app.alert("Could not open file: " .. filename)
      return
    end
    
    local fileData = file:read("*all")
    file:close()
    
    dbgMsg("File size: " .. #fileData .. " bytes")
    
    -- Find the zTXt chunk directly by searching for the keyword
    local ztxtPos = fileData:find("zTXtDescription", 1, true)
    if not ztxtPos then
      ztxtPos = fileData:find("zTXt", 1, true)
    end
    
    if ztxtPos then
      -- Go back 4 bytes to get the length
      if ztxtPos >= 5 then
        local lengthStart = ztxtPos - 4
        local b1 = string.byte(fileData, lengthStart)
        local b2 = string.byte(fileData, lengthStart + 1)
        local b3 = string.byte(fileData, lengthStart + 2)
        local b4 = string.byte(fileData, lengthStart + 3)
        
        -- Calculate chunk length
        local chunkLength = (b1 * 16777216) + (b2 * 65536) + (b3 * 256) + b4
        
        dbgMsg("Found zTXt chunk at position " .. ztxtPos .. " with length " .. chunkLength)
        
        -- Extract the entire chunk including length, type, data, and CRC
        rawZtxtChunk = fileData:sub(lengthStart, ztxtPos + 3 + chunkLength + 4)
        
        -- Save the metadata to a file
        saveMetadataToFile(rawZtxtChunk, "dmi_metadata.bin")
        
        dbgMsg("Extracted " .. #rawZtxtChunk .. " bytes of raw chunk data")
      else
        app.alert("Found zTXt chunk but could not determine length")
      end
    else
      app.alert("No zTXt chunk found in file")
    end
    
    -- Open the file in Aseprite
    app.command.OpenFile{ filename = filename }
    
    -- Reopen the dialog to show updated status
    showMainDialog()
  end
end

-- Export a DMI file
function exportDMI()
  if not app.activeSprite then
    app.alert("No sprite open to export")
    return
  end
  
  if not rawZtxtChunk then
    app.alert("No DMI metadata loaded. Please import a DMI file first.")
    return
  end
  
  local dlg = Dialog("Export DMI File")
  
  -- Pre-fill fields
  dlg:number{ id = "width", label = "Width:", text = "32", decimals = 0 }
  dlg:number{ id = "height", label = "Height:", text = "32", decimals = 0 }
  dlg:number{ id = "directions", label = "Directions:", text = "4", decimals = 0 }
  
  dlg:file{
    id = "file",
    label = "Save DMI File As:",
    filetypes = {"dmi"},
    save = true
  }
  dlg:button{ id = "ok", text = "OK" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()
  
  if dlg.data.ok and dlg.data.file ~= "" then
    local outputPath = dlg.data.file
    dbgMsg("Exporting to: " .. outputPath)
    
    -- Save current sprite as a temporary PNG
    local tempPngFile = "temp_dmi.png"
    app.command.SaveFile{
      filename = tempPngFile,
      filename_format = tempPngFile
    }
    
    -- Read the temporary PNG
    local file = io.open(tempPngFile, "rb")
    if not file then
      app.alert("Could not create temporary PNG file at: " .. tempPngFile)
      return
    end
    
    local pngData = file:read("*all")
    file:close()
    
    dbgMsg("Temp PNG size: " .. #pngData .. " bytes")
    
    -- Find the first IDAT chunk
    local idatPos = pngData:find("IDAT", 1, true)
    if not idatPos then
      app.alert("Could not find IDAT chunk in PNG")
      return
    end
    
    -- Go back 4 bytes to the start of the chunk
    idatPos = idatPos - 4
    
    -- Insert our raw zTXt chunk before the first IDAT chunk
    local outputData = pngData:sub(1, idatPos - 1) .. rawZtxtChunk .. pngData:sub(idatPos)
    
    -- Write the output file
    local outFile = io.open(outputPath, "wb")
    if not outFile then
      app.alert("Could not create output file: " .. outputPath)
      return
    end
    
    outFile:write(outputData)
    outFile:close()
    
    -- Try to clean up the temporary file without using os.remove
    safeRemoveFile(tempPngFile)
    
    app.alert("DMI file exported successfully to: " .. outputPath)
    
    -- Reopen the dialog
    showMainDialog()
  end
end

-- Start the script
showMainDialog()
