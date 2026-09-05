import numpy as np

import cv2
def reSizeDisplay(img1,img2,img3,scale_percent):
    scale_percent = 60 # percent of original size
    width = int(img1.shape[1] * scale_percent / 100)
    height = int(img1.shape[0] * scale_percent / 100)
    dim = (width, height)
    # resize image
    resized1 = cv2.resize(img1, dim, interpolation = cv2.INTER_AREA)
    resized2 = cv2.resize(img2, dim, interpolation = cv2.INTER_AREA)
    resized3 = cv2.resize(img3, dim, interpolation = cv2.INTER_AREA)
    
    numpy_horizontal = np.hstack((img1, img2,img3))
    numpy_horizontal_concat = np.concatenate((img1, img2, img3), axis=1)
    cv2.imshow('Numpy Horizontal Concat', numpy_horizontal_concat)
    cv2.moveWindow("Numpy Horizontal Concat", 0, 900)
 
image = cv2.imread('fish.png')
image2 = cv2.imread('fish.png')
image3 = cv2.imread('fish.png')

reSizeDisplay(image,image2,image3,60)
key = cv2.waitKey()
