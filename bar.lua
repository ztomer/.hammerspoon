-- Trying to make a status bar
-- Internaught 11/11/15

-- I guess this draws a border?
-- local boxBorder = 2

-- create some empty tables for our objects
local bars = {}
local iTunesBoxes = {}
local iTunesTimers = {}

-- grab the data, format the data
function updateiTunesBoxes()
    local artist = hs.itunes.getCurrentArtist()
    local album = hs.itunes.getCurrentAlbum()
    local track = hs.itunes.getCurrentTrack()

    local result = string.format("%s - %s", artist, track)

    for _,iTunesBox in ipairs(iTunesBoxes) do
        iTunesBox:setText(result)
    end
end

-- Lets draw the bar, on as many screens as we have, across the top
for _,screen in ipairs(hs.screen.allScreens()) do
        local frame = screen:frame()
        local box = hs.drawing.rectangle(hs.geometry.rect(frame.x, frame.y, frame.w, 25))
        table.insert(bars, box)

        box:setFillColor({["red"]=0.1,["blue"]=0.1,["green"]=0.1,["alpha"]=1}):setFill(true):show()
-- Create the iTunes box
        local text = hs.drawing.text(hs.geometry.rect(frame.x + 2, frame.y + 2, frame.w - 2, 20), "")
        table.insert(iTunesBoxes, text)
-- Set the text color
        text:setTextColor({["red"]=1,["blue"]=1,["green"]=1,["alpha"]=1})
-- Set the font size and font type
        text:setTextSize(14)
        text:setTextFont('Tamzen7x14')
-- Tuck it in, under notifications, under the "real" menubar
        box:setLevel(hs.drawing.windowLevels["floating"])
        text:setLevel(hs.drawing.windowLevels["floating"])
-- Show it off
        text:show()
end
-- Refresh the iTunes data every 3 seconds
local iTunesTimer = hs.timer.doEvery(3, updateiTunesBoxes):start()
updateiTunesBoxes()
