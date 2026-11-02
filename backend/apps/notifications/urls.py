from django.urls import path

from apps.customers.views import CustomerProfileView

from . import views

app_name = "notifications"

urlpatterns = [
    path("", views.NotificationListView.as_view(), name="list"),
    path("unread-count/", views.UnreadCountView.as_view(), name="unread-count"),
    path("read-all/", views.MarkReadView.as_view(), name="read-all"),
    path("<int:pk>/read/", views.MarkReadView.as_view(), name="read"),
    path("devices/", views.DeviceRegisterView.as_view(), name="device-register"),
    path("devices/unregister/", views.DeviceUnregisterView.as_view(), name="device-unregister"),
    # Names from the project document (section 10.8).
    path("register-device/", views.DeviceRegisterView.as_view(), name="register-device"),
    path("preferences/", CustomerProfileView.as_view(), name="preferences"),
]
