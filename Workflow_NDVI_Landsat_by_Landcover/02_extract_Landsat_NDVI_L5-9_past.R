# Pull all available Landsat NDVI; save by product; do not merge products into same file
# TO BE RUN ONCE!
# Steps for each landsat product:
# 1. Pull in the date for the area and date range we want: Jan 1, 2000 - today; filter/clip to our region
# 2. Do data cleaning: apply the appropriate bitmask, do band-level corrections
# 3. Mosaic images together with a middle-centered 15 day window (image date +/- 7 days); using a median reducer function
#      -->  mosiacking of images within a week on either side of a single image *should* help reduce spatial-based noise in NDVI
#    -- CONSIDER SAVING THESE IMAGES FOR LATER!
# 4. Create landcover-specific collections using the existing nlcd-based masks (see script 01) 
# 5. Reduce to the mean value for each image date
# 6. Save a file for each Landsat product (e.g. Landsat 7, Landsat 8) with the time series for each landcover class -- 1 value per landcover class per date

library(rgee); library(raster); library(terra)
ee_check() # For some reason, it's important to run this before initializing right now
rgee::ee_Initialize(user = 'crollinson@mortonarb.org', drive=T)
path.google.CR <- "~/Google Drive/My Drive/UrbanEcoDrought/"
path.google.share <- "~/Google Drive/Shared drives/Urban Ecological Drought/"
# GoogleFolderSave <- "UHI_Analysis_Output_Final_v2"
assetHome <- ee_get_assethome()

##################### 
# 0. Read in helper functions ----
##################### 
source("00_EarthEngine_HelperFunctions.R")
##################### 


##################### 
# Color Palette etc. ----
##################### 
# Setting the center point for the Arb because I think we'll have more variation
Map$setCenter(-88.04526, 41.81513, 11);

ndviVis = list(
  min= 0.0,
  max= 1,
  palette= c(
    '#FFFFFF', '#CE7E45', '#DF923D', '#F1B555', '#FCD163', '#99B718', '#74A901',
    '#66A000', '#529400', '#3E8601', '#207401', '#056201', '#004C00', '#023B01',
    '#012E01', '#011D01', '#011301'
    )
  )
##################### 

##################### 
# Read in Landcover Masks ----
##################### 
Chicago = ee$FeatureCollection("projects/breidyee/assets/SevenCntyChiReg") 
ee_print(Chicago)

chiBounds <- Chicago$geometry()$bounds()
chiBBox <- ee$Geometry$BBox(-88.70738, 41.20155, -87.52453, 42.49575)


forMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Forest')
# ee_print(forMask)
# Map$addLayer(forMask$select("YR2023"))

grassMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Grass')
# Map$addLayer(grassMask$select("YR2023"))

cropMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Crop')

urbOMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Urban-Open')

urbLMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Urban-Low')

urbMMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Urban-Medium')

urbHMask <- ee$Image('users/crollinson/NLCD-Chicago_2000-2023_Urban-High')

# Map$addLayer(urbLMask$select("YR2023"))
# Map$addLayer(forMask$select("YR2023"))
##################### 

##################### 
# Read in & Format Landsat 8 ----
##################### 
# "LANDSAT/LC08/C02/T1_RT"
# Load MODIS NDVI data; attach month & year
# https:#developers.google.com/earth-engine/datasets/catalog/LANDSAT_LC08_C02_T1_L2
landsat8 <- ee$ImageCollection("LANDSAT/LC08/C02/T1_L2")$filterBounds(Chicago)$map(function(image){
  return(image$clip(Chicago))
})$map(function(img){
  d= ee$Date(img$get('system:time_start'));
  dy= d$get('day');    
  m= d$get('month');
  y= d$get('year');
  
  # # Add masks 
  img <- applyLandsatBitMask(img)
  
  # #scale correction; doing here & separating form NDVI so it gets saved on the image
  lAdj = img$select(c('SR_B1', 'SR_B2', 'SR_B3', 'SR_B4', 'SR_B5', 'SR_B6', 'SR_B7'))$multiply(0.0000275)$add(-0.2);
  lst_k = img$select('ST_B10')$multiply(0.00341802)$add(149);

  # img3 = img2$addBands(srcImg=lAdj, overwrite=T)$addBands(srcImg=lst_k, overwrite=T)$set('date',d, 'day',dy, 'month',m, 'year',y)
  return(img$addBands(srcImg=lAdj, overwrite=T)$addBands(srcImg=lst_k, overwrite=T)$set('date',d, 'day',dy, 'month',m, 'year',y))
})$select(c('SR_B2', 'SR_B3', 'SR_B4', 'SR_B5', 'SR_B6', 'SR_B7', 'ST_B10'),c('blue', 'green', 'red', 'nir', 'swir1', 'swir2', 'LST_K'))$map(addNDVI)
# Map$addLayer(landsat8$first()$select('NDVI'), ndviVis, "NDVI - First")
# ee_print(landsat8)
# Map$addLayer(landsat8$first()$select('NDVI'))

l8Mosaic = mosaicByDate(landsat8, 7)$select(c('blue_median', 'green_median', 'red_median', 'nir_median', 'swir1_median', 'swir2_median', 'LST_K_median', "NDVI_median"),c('blue', 'green', 'red', 'nir', 'swir1', 'swir2', 'LST_K', "NDVI"))$sort("date")
# ee_print(l8Mosaic, "landsat8-Mosaic")
# Map$addLayer(l8Mosaic$first()$select('NDVI'), ndviVis, "NDVI - First")
##################### 

##################### 
# Mask NDVI by Landcover & condense to regional means ----
##################### 
ndviForYear <- extractByLC(l8Mosaic, forMask)
ndviGrassYear <- extractByLC(l8Mosaic, grassMask)
ndviCropYear <- extractByLC(l8Mosaic, cropMask)

ndviUrbOYear <- extractByLC(l8Mosaic, urbOMask)
ndviUrbLYear <- extractByLC(l8Mosaic, urbLMask)
ndviUrbMYear <- extractByLC(l8Mosaic, urbMMask)
ndviUrbHYear <- extractByLC(l8Mosaic, urbHMask)
# Map$addLayer(ndviUrbLYear$select("NDVI")$first(), ndviVis, "Forest NDVI") # It worked!!


######### ************************** ######### 
# reduce regions: ----
ForMeans = ee$FeatureCollection(ndviForYear$map(regionNDVIMean))
GrassMeans = ee$FeatureCollection(ndviGrassYear$map(regionNDVIMean))
CropMeans = ee$FeatureCollection(ndviCropYear$map(regionNDVIMean))

UrbOMeans = ee$FeatureCollection(ndviUrbOYear$map(regionNDVIMean))
UrbLMeans = ee$FeatureCollection(ndviUrbLYear$map(regionNDVIMean))
UrbMMeans = ee$FeatureCollection(ndviUrbMYear$map(regionNDVIMean))
UrbHMeans = ee$FeatureCollection(ndviUrbHYear$map(regionNDVIMean))
# ee_print(UrbLMeans, "UrbL Means") # 

# # # # Saving the outputs!
ForMeansSave <- ee_table_to_drive(collection=ForMeans, 
                                   description="Save_Forest-Means_Landsat8",
                                   folder="UrbanEcoDrought_TEST",
                                   fileNamePrefix="Landsat8_Forest",
                                   timePrefix=T,
                                   fileFormat="CSV",
                                   selectors=c("date", "NDVI"))
ForMeansSave$start()

GrassMeansSave <- ee_table_to_drive(collection=GrassMeans, 
                                  description="Save_Grassland-Means_Landsat8",
                                  folder="UrbanEcoDrought_TEST",
                                  fileNamePrefix="Landsat8_Grassland",
                                  timePrefix=T,
                                  fileFormat="CSV",
                                  selectors=c("date", "NDVI"))
GrassMeansSave$start()

CropMeansSave <- ee_table_to_drive(collection=CropMeans, 
                                    description="Save_Crop-Means_Landsat8",
                                    folder="UrbanEcoDrought_TEST",
                                    fileNamePrefix="Landsat8_Crop",
                                    timePrefix=T,
                                    fileFormat="CSV",
                                    selectors=c("date", "NDVI"))
CropMeansSave$start()


UrbOMeansSave <- ee_table_to_drive(collection=UrbOMeans, 
                                  description="Save_Urb-O-Means_Landsat8",
                                  folder="UrbanEcoDrought_TEST",
                                  fileNamePrefix="Landsat8_Urban-Open",
                                  timePrefix=T,
                                  fileFormat="CSV",
                                  selectors=c("date", "NDVI"))
UrbOMeansSave$start()


UrbLMeansSave <- ee_table_to_drive(collection=UrbLMeans, 
                                   description="Save_Urb-L-Means_Landsat8",
                                   folder="UrbanEcoDrought_TEST",
                                   fileNamePrefix="Landsat8_Urban-Low",
                                   timePrefix=T,
                                   fileFormat="CSV",
                                   selectors=c("date", "NDVI"))
UrbLMeansSave$start()

UrbMMeansSave <- ee_table_to_drive(collection=UrbMMeans, 
                                   description="Save_Urb-M-Means_Landsat8",
                                   folder="UrbanEcoDrought_TEST",
                                   fileNamePrefix="Landsat8_Urban-Medium",
                                   timePrefix=T,
                                   fileFormat="CSV",
                                   selectors=c("date", "NDVI"))
UrbMMeansSave$start()

UrbHMeansSave <- ee_table_to_drive(collection=UrbHMeans, 
                                   description="Save_Urb-H-Means_Landsat8",
                                   folder="UrbanEcoDrought_TEST",
                                   fileNamePrefix="Landsat8_Urban-High",
                                   timePrefix=T,
                                   fileFormat="CSV",
                                   selectors=c("date", "NDVI"))
UrbHMeansSave$start()



# test <- read.csv("~/Google Drive/My Drive/UrbanEcoDrought_TEST/Landsat8_Urban-High_2023_07_11_16_31_03.csv")
# test$date <- as.Date(test$date)
# test$year <- lubridate::year(test$date)
# test$yday <- lubridate::yday(test$date)
# summary(test)
# # 
# library(ggplot2)
# ggplot(data=test) +
#   geom_line(aes(x=yday, y=NDVI, group=year))

