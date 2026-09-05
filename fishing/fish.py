import datetime 
import time


import numpy as np
import cv2

from imutils.video import VideoStream # intsall
import imutils # install
from pynput.mouse import Button, Controller # install
import mss # intsall 
import screeninfo  # install

 


mouse = Controller()


# MAIN
mac=0
if(mac):
    offset=0
else:
    offset=40

mac=1
minAr=300


def reSizeDisplay(img1,img2,img3,scale_percent):
    scale_percent = 60 # percent of original size
    width = int(img1.shape[1] * scale_percent / 100)
    height = int(img1.shape[0] * scale_percent / 100)
    dim = (width, height)




    img1 = cv2.cvtColor(img1, cv2.COLOR_GRAY2BGR)
    img2 = cv2.cvtColor(img2, cv2.COLOR_GRAY2RGB)
    img3 = cv2.cvtColor(img3, cv2.COLOR_GRAY2RGB)

    resized1 = cv2.resize(img1, dim, interpolation = cv2.INTER_AREA)
    resized2 = cv2.resize(img2, dim, interpolation = cv2.INTER_AREA)
    resized3 = cv2.resize(img3, dim, interpolation = cv2.INTER_AREA)
    
    print(resized1.size)
    print(resized2.size)
    print(resized3.size)
 
    numpy_horizontal = np.hstack((resized3, resized1,resized2))
    numpy_horizontal_concat = np.concatenate((resized3, resized1,resized2), axis=1)
    cv2.imshow('Numpy Horizontal Concat', numpy_horizontal_concat)
    cv2.moveWindow("Numpy Horizontal Concat", 0, 900)
 



class Frames:
    


    def __init__(self):
        self.firstFrame = None
        self.lastClicked=0
        self.text = "Unoccupied"

    def prosessFrame(self,frame):

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        # if the first frame is None, initialize it
        if self.firstFrame is None:
            self.firstFrame = gray
            self.fish()
            return 0

        print("sadasd")
        # compute the absolute difference between the current frame and
        # first frame
        frameDelta = cv2.absdiff(self.firstFrame, gray)
        thresh = cv2.threshold(frameDelta, 60, 255, cv2.THRESH_BINARY)[1]

        # dilate the thresholded image to fill in holes, then find contours
        # on thresholded image
        thresh = cv2.dilate(thresh, None, iterations=2)
        cnts = cv2.findContours(thresh.copy(), cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE)
        cnts = imutils.grab_contours(cnts)

        # loop over the contours
        for c in cnts:
            # if the contour is too small, ignore it
            if cv2.contourArea(c) < minAr:
                continue

            # compute the bounding box for the contour, draw it on the frame,
            # and update the text
            (x, y, w, h) = cv2.boundingRect(c)
            #¤%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            # FOR tekst
            if(y<250):
                continue
            else:
                self.fish()
            self.click(x, y, w, h)
            cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 255, 0), 2)
            self.text = "Occupied"

        # draw the text and timestamp on the frame
        cv2.putText(frame, "Room Status: {}".format(self.text), (10, 20),
            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
        cv2.putText(frame, datetime.datetime.now().strftime("%A %d %B %Y %I:%M:%S%p"),
            (10, frame.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 0, 255), 1)

        # show the frame and record if the user presses a key
        reSizeDisplay(thresh,frameDelta,gray,60)
        key = cv2.waitKey(1) & 0xFF

        # if the `q` key is pressed, break from the lop
        return 0

    def click(self,x, y, w, h):
        # Set pointer position
        mouse.position = (x+w, y+ h+offset)
        print('Now we have moved it to {0}'.format(
            mouse.position))
        time.sleep(2)
        # Press and release
        #¤%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        # FOR box med fisk
        if(y <400 and x<400):
            mouse.position = (x+w, y+ h)
            mouse.press(Button.left)
            mouse.release(Button.left)
            time.sleep(2)
            self.fish()

        else:
            mouse.press(Button.right)
            mouse.release(Button.right)
            time.sleep(2)

    def fish(self):
        # goto 280,1100 #linux
        mouse.position = (280,1150)
        mouse.press(Button.left)
        mouse.release(Button.left)
        return 0


frames = Frames()

with mss.mss() as sct:

    monitor_number = 1
    mon = sct.monitors[0]
    w,h=1280,800

    print(mon["left"])
    monitor = {
        "top": mon["top"]+ 0+offset, #mon["top"] +  # 0px from the top
        "left": mon["left"]+0,  # 0px from the left
        "width": w,
        "height": h,
        "mon": monitor_number,
    }

    while "Screen capturing":
        last_time = time.time()


        img = np.array(sct.grab(monitor))

        #cv2.imshow("OpenCV/Numpy normal", img)
        frames.prosessFrame(img)

        print("fps: {}".format(1 / (time.time() - last_time)))

        # Press "q" to quit
        if cv2.waitKey(25) & 0xFF == ord("q"):
            cv2.destroyAllWindows()
            break





