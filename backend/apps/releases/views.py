from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AppRelease


class LatestReleaseView(APIView):
    """GET /app/latest/?platform=android&current=<build number>

    Returns the newest active release, and whether the caller must update: forced if any newer release
    marked "force update" exists (so skipping a forced version is not possible)."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(
        parameters=[OpenApiParameter("platform", str), OpenApiParameter("current", int)],
        responses={200: OpenApiTypes.OBJECT},
    )
    def get(self, request):
        platform = request.query_params.get("platform", AppRelease.Platform.ANDROID)
        releases = AppRelease.objects.filter(platform=platform, is_active=True)
        latest = releases.first()
        if latest is None:
            return Response({"update_available": False})
        try:
            current = int(request.query_params.get("current", 0))
        except ValueError:
            current = 0
        newer = releases.filter(version_code__gt=current)
        return Response({
            "update_available": newer.exists(),
            "force": newer.filter(force_update=True).exists(),
            "version_code": latest.version_code,
            "version_name": latest.version_name,
            "apk_url": latest.apk_url,
            "notes": latest.notes,
        })
