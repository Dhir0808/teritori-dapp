import React, { FC } from "react";
import { ScrollView, useWindowDimensions } from "react-native";

import { FeedHeader } from "./FeedHeader";

import { MobileTitle } from "@/components/ScreenContainer/ScreenContainerMobile";
import { FeedMusicList } from "@/components/music/FeedMusicList";
import { useIsMobile } from "@/hooks/useIsMobile";
import { useMaxResolution } from "@/hooks/useMaxResolution";
import { useSelectedNetworkId } from "@/hooks/useSelectedNetwork";
import {
  RESPONSIVE_BREAKPOINT_S,
  screenContentMaxWidth,
} from "@/utils/style/layout";

export const MusicFeed: FC = () => {
  const { width: windowWidth } = useWindowDimensions();
  const { width, height } = useMaxResolution();
  const isMobile = useIsMobile();
  const selectedNetworkId = useSelectedNetworkId();
  return (
    <ScrollView style={{ height }}>
      {/* ScreenContainer in FeedScreen has noScroll, so we need to add MobileTitle here */}
      {isMobile && <MobileTitle title="SOCIAL FEED" />}
      <FeedHeader selectedTab="music" />
      <FeedMusicList
        title="All music"
        networkId={selectedNetworkId}
        allowUpload
        style={{
          alignSelf: "center",
          width: windowWidth < RESPONSIVE_BREAKPOINT_S ? windowWidth : width,
          maxWidth: screenContentMaxWidth,
        }}
      />
    </ScrollView>
  );
};
