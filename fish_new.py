import cv2, mss
import numpy as np
import time

# Define the window dimensions
screen_width = 800
screen_height = 600
x = 0
y = 0
padding = 20
# init prev img
prev_img= np.zeros((screen_height, screen_width), np.uint8)

max_area = 160
min_area = 50



# a cycle is 30 seconds

# Initialize the mss screen capture object
sct = mss.mss()

cv2.namedWindow("Screen Capture", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Screen Capture", (screen_width, screen_height))
cv2.moveWindow("Screen Capture", screen_width+padding, 0)

def checkifintitedright():
    # detect ocr
    # if not inited right
    
    print()

def checkforpngmatch(grayimg):

    #cv2.absdiff("")
    print()


def checkforimgdiff(grayimg,screen):
    diff = cv2.absdiff(grayimg, prev_img)
    threshold = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)[1]
    contours = cv2.findContours(threshold, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = contours[0] if len(contours) == 2 else contours[1]
    for c in contours:
        if cv2.contourArea(c) > min_area and cv2.contourArea(c) < max_area:
            print(cv2.contourArea(c))
            print("asasda")
            (x, y, w, h) = cv2.boundingRect(c)
            cv2.rectangle(screen, (x, y), (x + w, y + h), (0, 255, 0), 2)
    return threshold

# todo put in a voting system
    

while True:
    screen = np.array(sct.grab({"top": y, "left": x, "width": screen_width, "height": screen_height}))
    gray = cv2.cvtColor(screen, cv2.COLOR_BGR2GRAY)
    screen=checkforimgdiff(gray,screen)

    cv2.imshow("Screen Capture",screen)
    

    if cv2.waitKey(25) & 0xFF == ord('q'):
        break

    # Sleep for 50ms
    time.sleep(0.03)
    prev_img=gray
# Destroy the window
cv2.destroyAllWindows()
